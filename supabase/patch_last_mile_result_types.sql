-- VINEXPRESS - Sửa kiểu dữ liệu hàm công việc nhân viên lấy/giao hàng.
-- Chạy an toàn: chỉ thay nội dung hàm, không xóa bảng và không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2()
RETURNS TABLE(
  id BIGINT,
  ma_van_don VARCHAR,
  ma_qr UUID,
  loai_cong_viec TEXT,
  ten_khach TEXT,
  so_dien_thoai TEXT,
  dia_chi TEXT,
  ten_kho TEXT,
  trang_thai VARCHAR,
  da_nhan BOOLEAN,
  ngay_cap_nhat TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path=public
AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
BEGIN
  SELECT nv.* INTO v_nv
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro IN ('NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG')
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản chưa được duyệt hoặc không đúng vai trò';
  END IF;

  RETURN QUERY
  SELECT
    dh.id,
    dh.ma_van_don::VARCHAR,
    dh.ma_qr,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN 'LAY_HANG' ELSE 'GIAO_HANG' END)::TEXT,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nguoi_gui_ten ELSE dh.nguoi_nhan_ten END)::TEXT,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nguoi_gui_sdt ELSE dh.nguoi_nhan_sdt END)::TEXT,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nguoi_gui_dia_chi ELSE dh.nguoi_nhan_dia_chi END)::TEXT,
    kh.ten_kho::TEXT,
    dh.trang_thai::VARCHAR,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nhan_vien_lay_hang_id=v_nv.id
      ELSE dh.nhan_vien_giao_hang_id=v_nv.id END,
    dh.ngay_cap_nhat
  FROM public.don_hang dh
  JOIN public.kho_hang kh ON kh.id=CASE
    WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN dh.kho_gui_id
    ELSE dh.kho_dich_id END
  WHERE (
    v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
    AND dh.kho_gui_id=v_nv.kho_hang_id
    AND dh.khu_vuc_lay_hang_id=v_nv.khu_vuc_id
    AND dh.trang_thai='CHO_LAY_HANG'
    AND (dh.nhan_vien_lay_hang_id IS NULL OR dh.nhan_vien_lay_hang_id=v_nv.id)
  ) OR (
    v_nv.vai_tro='NHAN_VIEN_GIAO_HANG'
    AND dh.nhan_vien_giao_hang_id=v_nv.id
    AND dh.trang_thai IN ('DEN_KHO_DICH','GIAO_CHO_SHIPPER','DANG_GIAO_HANG')
  )
  ORDER BY dh.ngay_cap_nhat;
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2() TO authenticated;

NOTIFY pgrst,'reload schema';
