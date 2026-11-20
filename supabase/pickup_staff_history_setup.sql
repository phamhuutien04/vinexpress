-- Lịch sử đơn đã nhận của nhân viên lấy hàng. Không sửa dữ liệu cũ.
CREATE OR REPLACE FUNCTION public.nhan_vien_lay_hang_lich_su()
RETURNS TABLE (
  id BIGINT,
  ma_van_don VARCHAR,
  dia_chi TEXT,
  trang_thai VARCHAR,
  ngay_lay_hang TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_nhan_vien_id BIGINT;
BEGIN
  SELECT nv.id INTO v_nhan_vien_id
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id = auth.uid()
    AND nv.vai_tro = 'NHAN_VIEN_LAY_HANG';
  IF v_nhan_vien_id IS NULL THEN
    RAISE EXCEPTION 'Chỉ nhân viên lấy hàng mới xem được lịch sử này';
  END IF;
  RETURN QUERY
  SELECT dh.id, dh.ma_van_don::VARCHAR, dh.nguoi_gui_dia_chi,
         dh.trang_thai::VARCHAR, dh.ngay_lay_hang
  FROM public.don_hang dh
  WHERE dh.nhan_vien_lay_hang_id = v_nhan_vien_id
    AND dh.trang_thai <> 'CHO_LAY_HANG'
  ORDER BY dh.ngay_lay_hang DESC NULLS LAST, dh.ngay_cap_nhat DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.nhan_vien_lay_hang_lich_su() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_lay_hang_lich_su() TO authenticated;
NOTIFY pgrst, 'reload schema';
