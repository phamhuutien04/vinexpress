-- VINEXPRESS - Cho nhân viên lấy hàng đọc tọa độ điểm lấy để chỉ đường.
-- Bản vá an toàn: không xóa bảng và không làm mất dữ liệu.

CREATE OR REPLACE FUNCTION public.toa_do_diem_lay_nhan_vien(
  p_don_hang_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_nhan_vien public.nhan_vien%ROWTYPE;
  v_don_hang public.don_hang%ROWTYPE;
  v_kho_dia_chi TEXT;
BEGIN
  SELECT nv.* INTO v_nhan_vien
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id = auth.uid()
    AND nv.vai_tro = 'NHAN_VIEN_LAY_HANG'
    AND nv.trang_thai_duyet = 'DA_DUYET'
    AND nv.trang_thai = 'HOAT_DONG';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản không phải nhân viên lấy hàng đang hoạt động';
  END IF;

  SELECT dh.* INTO v_don_hang
  FROM public.don_hang dh
  WHERE dh.id = p_don_hang_id
    AND dh.nhan_vien_lay_hang_id = v_nhan_vien.id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Đơn hàng chưa được nhân viên này nhận';
  END IF;

  SELECT kh.dia_chi INTO v_kho_dia_chi
  FROM public.kho_hang kh
  WHERE kh.id = v_nhan_vien.kho_hang_id
    AND kh.cap_kho = 2;

  RETURN jsonb_build_object(
    'nguoi_gui_vi_do', v_don_hang.nguoi_gui_vi_do,
    'nguoi_gui_kinh_do', v_don_hang.nguoi_gui_kinh_do,
    'kho_dia_chi', v_kho_dia_chi
  );
END;
$$;

REVOKE ALL ON FUNCTION public.toa_do_diem_lay_nhan_vien(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.toa_do_diem_lay_nhan_vien(BIGINT) TO authenticated;
NOTIFY pgrst, 'reload schema';
