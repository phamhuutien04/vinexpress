-- Đơn trên 50 km dùng xe tải và lấy phí từ bảng phi_van_chuyen.
-- Chạy an toàn, không xóa dữ liệu.

ALTER TABLE public.phi_van_chuyen
ADD COLUMN IF NOT EXISTS phi_xe_tai NUMERIC(14,2)
  NOT NULL DEFAULT 30000 CHECK(phi_xe_tai>=0);

ALTER TABLE public.phi_van_chuyen
ADD COLUMN IF NOT EXISTS phi_moi_kg NUMERIC(14,2)
  NOT NULL DEFAULT 3000 CHECK(phi_moi_kg>=0);

-- ADD COLUMN với DEFAULT đã tự điền 30.000đ và 3.000đ cho các dòng hiện có,
-- nên không cần chạy thêm UPDATE (tránh lỗi khi chỉ chạy một phần câu lệnh).

CREATE OR REPLACE FUNCTION public.lay_cau_hinh_phi_van_chuyen()
RETURNS JSONB LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT jsonb_build_object(
    'phi_xe_may_moi_km',COALESCE(pvc.phi_van_chuyen,5000),
    'phi_xe_tai',COALESCE(pvc.phi_xe_tai,30000),
    'phi_moi_kg',COALESCE(pvc.phi_moi_kg,3000),
    'phan_tram_san',COALESCE(pvc.phan_tram_san,20)
  )
  FROM public.phi_van_chuyen pvc WHERE pvc.id=1;
$$;

CREATE OR REPLACE FUNCTION public.ap_dung_phi_mac_dinh_xe_tai()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$
DECLARE
  v_phi_xe_tai NUMERIC;
  v_phi_moi_kg NUMERIC;
  v_so_kg_tinh_phi BIGINT;
BEGIN
  IF NEW.phuong_tien='XE_TAI' AND NEW.khoang_cach_km>50 THEN
    SELECT pvc.phi_xe_tai,pvc.phi_moi_kg
    INTO v_phi_xe_tai,v_phi_moi_kg
    FROM public.phi_van_chuyen pvc WHERE pvc.id=1;
    v_so_kg_tinh_phi := CASE
      WHEN COALESCE(NEW.can_nang,0)<1 THEN 0
      ELSE FLOOR(NEW.can_nang)::BIGINT
    END;
    NEW.phi_van_chuyen := COALESCE(v_phi_xe_tai,30000)
      + v_so_kg_tinh_phi*COALESCE(v_phi_moi_kg,3000);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_phi_mac_dinh_xe_tai ON public.don_hang;
CREATE TRIGGER trg_phi_mac_dinh_xe_tai
BEFORE INSERT OR UPDATE OF phuong_tien,khoang_cach_km,phi_van_chuyen,can_nang
ON public.don_hang FOR EACH ROW
EXECUTE FUNCTION public.ap_dung_phi_mac_dinh_xe_tai();

REVOKE ALL ON FUNCTION public.lay_cau_hinh_phi_van_chuyen() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lay_cau_hinh_phi_van_chuyen() TO authenticated;

NOTIFY pgrst,'reload schema';
