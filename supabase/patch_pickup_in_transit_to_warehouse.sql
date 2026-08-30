-- VINEXPRESS - Tách trạng thái đã lấy khỏi trạng thái đã nhập kho.
-- DA_LAY_HANG: nhân viên đang mang kiện từ khách về kho.
-- DEN_KHO_TRUNG_CHUYEN / DEN_KHO_DICH: nhân viên kho đã quét QR nhập kho.

CREATE OR REPLACE FUNCTION public.khong_tu_dong_nhap_kho_khi_lay_hang()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vai_tro TEXT;
BEGIN
  IF OLD.trang_thai = 'CHO_LAY_HANG'
     AND NEW.trang_thai = 'DA_LAY_HANG'
     AND NEW.nhan_vien_hien_tai_id IS NOT NULL THEN
    SELECT nv.vai_tro INTO v_vai_tro
    FROM public.nhan_vien nv
    WHERE nv.id = NEW.nhan_vien_hien_tai_id;

    IF v_vai_tro = 'NHAN_VIEN_LAY_HANG' THEN
      NEW.kho_hien_tai_id := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_khong_tu_dong_nhap_kho_khi_lay_hang
  ON public.don_hang;
CREATE TRIGGER trg_khong_tu_dong_nhap_kho_khi_lay_hang
BEFORE UPDATE OF trang_thai, kho_hien_tai_id ON public.don_hang
FOR EACH ROW
EXECUTE FUNCTION public.khong_tu_dong_nhap_kho_khi_lay_hang();

-- Sửa các đơn đang bị đánh dấu ở kho quá sớm. Không ảnh hưởng đơn đã được
-- nhân viên kho quét sang DEN_KHO_TRUNG_CHUYEN hoặc DEN_KHO_DICH.
UPDATE public.don_hang dh
SET kho_hien_tai_id = NULL,
    ngay_cap_nhat = NOW()
FROM public.nhan_vien nv
WHERE dh.trang_thai = 'DA_LAY_HANG'
  AND dh.nhan_vien_hien_tai_id = nv.id
  AND nv.vai_tro = 'NHAN_VIEN_LAY_HANG'
  AND dh.kho_hien_tai_id = dh.kho_gui_id;

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_tong_quan()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE; v_kho public.kho_hang%ROWTYPE;
BEGIN
  SELECT * INTO v_nv FROM public.nhan_vien
  WHERE auth_user_id=auth.uid() AND vai_tro='NHAN_VIEN_KHO'
    AND trang_thai_duyet='DA_DUYET' AND trang_thai='HOAT_DONG';
  IF NOT FOUND OR v_nv.kho_hang_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;
  SELECT * INTO v_kho FROM public.kho_hang WHERE id=v_nv.kho_hang_id;
  RETURN jsonb_build_object(
    'nhan_vien_id',v_nv.id,'ho_ten',v_nv.ho_ten,
    'so_dien_thoai',v_nv.so_dien_thoai,'email',v_nv.email,
    'kho_id',v_kho.id,'ma_kho',v_kho.ma_kho,'ten_kho',v_kho.ten_kho,
    'dia_chi',v_kho.dia_chi,'cap_kho',v_kho.cap_kho,
    'don_tai_kho',(SELECT COUNT(*) FROM public.don_hang dh
      WHERE dh.kho_hien_tai_id=v_kho.id),
    'cho_xu_ly',(SELECT COUNT(*) FROM public.don_hang dh
      WHERE dh.kho_hien_tai_id=v_kho.id
        AND dh.trang_thai IN ('DEN_KHO_TRUNG_CHUYEN','DEN_KHO_DICH')),
    'da_xu_ly_hom_nay',(SELECT COUNT(*) FROM public.nhat_ky_don_hang nk
      WHERE nk.nhan_vien_id=v_nv.id AND nk.thoi_gian::DATE=CURRENT_DATE)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_don_can_xu_ly()
RETURNS TABLE(id BIGINT,ma_van_don VARCHAR,nguoi_gui_ten VARCHAR,
  nguoi_nhan_ten VARCHAR,nguoi_nhan_dia_chi TEXT,can_nang NUMERIC,
  trang_thai VARCHAR,ngay_cap_nhat TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_kho_id BIGINT;
BEGIN
  SELECT nv.kho_hang_id INTO v_kho_id FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF v_kho_id IS NULL THEN RAISE EXCEPTION 'Nhân viên chưa được gán kho'; END IF;
  RETURN QUERY
  SELECT dh.id,dh.ma_van_don::VARCHAR,dh.nguoi_gui_ten::VARCHAR,
    dh.nguoi_nhan_ten::VARCHAR,dh.nguoi_nhan_dia_chi,dh.can_nang,
    dh.trang_thai::VARCHAR,dh.ngay_cap_nhat
  FROM public.don_hang dh
  WHERE dh.kho_hien_tai_id=v_kho_id
  ORDER BY dh.ngay_cap_nhat DESC LIMIT 200;
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_kho_tong_quan() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nhan_vien_kho_don_can_xu_ly() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_tong_quan() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_don_can_xu_ly() TO authenticated;
NOTIFY pgrst, 'reload schema';
