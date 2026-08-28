-- VINEXPRESS - Đối soát phí tiền mặt của đơn SHIPPER không COD.
-- Bản vá an toàn, không xóa bảng và không xóa dữ liệu.

ALTER TABLE public.giao_dich_vi
  DROP CONSTRAINT IF EXISTS giao_dich_vi_loai_check;
ALTER TABLE public.giao_dich_vi
  DROP CONSTRAINT IF EXISTS chk_giao_dich_vi_loai;
ALTER TABLE public.giao_dich_vi
  ADD CONSTRAINT chk_giao_dich_vi_loai CHECK (loai IN (
    'NAP_TIEN','RUT_TIEN','YEU_CAU_RUT','HOAN_RUT',
    'TRU_COD','NHAN_COD','HOAN_COD','THU_NHAP_GIAO_HANG',
    'TRU_PHI_LAY_HANG','DIEU_CHINH'
  ));

CREATE OR REPLACE FUNCTION public.tru_phi_lay_hang_shipper_khong_cod()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vai_tro TEXT;
  v_vi_id BIGINT;
  v_so_du NUMERIC;
  v_so_tien NUMERIC := COALESCE(NEW.phi_van_chuyen, 0);
BEGIN
  IF OLD.trang_thai IS DISTINCT FROM 'CHO_LAY_HANG'
     OR NEW.trang_thai IS DISTINCT FROM 'DA_LAY_HANG'
     OR COALESCE(NEW.cod, 0) > 0
     OR v_so_tien <= 0
     OR NEW.nhan_vien_hien_tai_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT nv.vai_tro INTO v_vai_tro
  FROM public.nhan_vien nv
  WHERE nv.id = NEW.nhan_vien_hien_tai_id;

  -- Nhân viên lấy hàng có luồng đối soát riêng; trigger này chỉ dành cho SHIPPER.
  IF v_vai_tro IS DISTINCT FROM 'SHIPPER' THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.vi(nhan_vien_id)
  VALUES (NEW.nhan_vien_hien_tai_id)
  ON CONFLICT (nhan_vien_id) DO NOTHING;

  SELECT v.id, v.so_du INTO v_vi_id, v_so_du
  FROM public.vi v
  WHERE v.nhan_vien_id = NEW.nhan_vien_hien_tai_id
  FOR UPDATE;

  IF EXISTS (
    SELECT 1 FROM public.giao_dich_vi gd
    WHERE gd.vi_id = v_vi_id
      AND gd.don_hang_id = NEW.id
      AND gd.loai = 'TRU_PHI_LAY_HANG'
  ) THEN
    RETURN NEW;
  END IF;

  IF COALESCE(v_so_du, 0) < v_so_tien THEN
    RAISE EXCEPTION
      'Số dư ví không đủ để đối soát phí vận chuyển. Cần %đ, số dư %đ. Vui lòng nạp ví',
      ROUND(v_so_tien), ROUND(COALESCE(v_so_du, 0));
  END IF;

  UPDATE public.vi
  SET so_du = so_du - v_so_tien,
      ngay_cap_nhat = NOW()
  WHERE id = v_vi_id
  RETURNING so_du INTO v_so_du;

  INSERT INTO public.giao_dich_vi(
    vi_id, don_hang_id, loai, so_tien, so_du_sau, noi_dung
  ) VALUES (
    v_vi_id, NEW.id, 'TRU_PHI_LAY_HANG', v_so_tien, v_so_du,
    'Đối soát phí vận chuyển tiền mặt shipper đã thu từ người gửi (đơn không COD)'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tru_phi_lay_hang_shipper_khong_cod
  ON public.don_hang;
CREATE TRIGGER trg_tru_phi_lay_hang_shipper_khong_cod
BEFORE UPDATE OF trang_thai ON public.don_hang
FOR EACH ROW
EXECUTE FUNCTION public.tru_phi_lay_hang_shipper_khong_cod();

NOTIFY pgrst, 'reload schema';
