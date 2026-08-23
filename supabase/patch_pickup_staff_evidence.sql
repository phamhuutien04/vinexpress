-- VINEXPRESS - Nhân viên lấy hàng chụp minh chứng trong bán kính 500 m.
-- Bản vá an toàn: không xóa bảng, không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.nhan_vien_lay_hang_xac_nhan_minh_chung(
  p_don_hang_id BIGINT,
  p_minh_chung TEXT,
  p_vi_do DOUBLE PRECISION,
  p_kinh_do DOUBLE PRECISION,
  p_diem_lay_vi_do DOUBLE PRECISION,
  p_diem_lay_kinh_do DOUBLE PRECISION
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
  v_don public.don_hang%ROWTYPE;
  v_diem_lay_vi_do DOUBLE PRECISION;
  v_diem_lay_kinh_do DOUBLE PRECISION;
  v_khoang_cach_met DOUBLE PRECISION;
BEGIN
  SELECT nv.* INTO v_nv
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id = auth.uid()
    AND nv.vai_tro = 'NHAN_VIEN_LAY_HANG'
    AND nv.trang_thai_duyet = 'DA_DUYET'
    AND nv.trang_thai = 'HOAT_DONG';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản không phải nhân viên lấy hàng đang hoạt động';
  END IF;

  SELECT dh.* INTO v_don
  FROM public.don_hang dh
  WHERE dh.id = p_don_hang_id
  FOR UPDATE;

  IF NOT FOUND OR v_don.nhan_vien_lay_hang_id IS DISTINCT FROM v_nv.id
     OR v_don.trang_thai <> 'CHO_LAY_HANG' THEN
    RAISE EXCEPTION 'Đơn hàng không thuộc nhân viên hoặc không còn chờ lấy';
  END IF;

  IF p_minh_chung IS NULL OR BTRIM(p_minh_chung) = '' THEN
    RAISE EXCEPTION 'Bắt buộc có ảnh minh chứng lấy hàng';
  END IF;

  v_diem_lay_vi_do := COALESCE(v_don.nguoi_gui_vi_do, p_diem_lay_vi_do);
  v_diem_lay_kinh_do := COALESCE(v_don.nguoi_gui_kinh_do, p_diem_lay_kinh_do);
  IF p_vi_do IS NULL OR p_kinh_do IS NULL
     OR v_diem_lay_vi_do IS NULL OR v_diem_lay_kinh_do IS NULL THEN
    RAISE EXCEPTION 'Thiếu tọa độ để xác minh khoảng cách';
  END IF;

  v_khoang_cach_met := 6371000 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(v_diem_lay_vi_do - p_vi_do) / 2), 2)
    + COS(RADIANS(p_vi_do)) * COS(RADIANS(v_diem_lay_vi_do))
    * POWER(SIN(RADIANS(v_diem_lay_kinh_do - p_kinh_do) / 2), 2)
  ));
  IF v_khoang_cach_met > 500 THEN
    RAISE EXCEPTION 'Chỉ được xác nhận trong phạm vi 500 m. Hiện cách % m',
      ROUND(v_khoang_cach_met);
  END IF;

  UPDATE public.don_hang
  SET trang_thai = 'DA_LAY_HANG',
      kho_hien_tai_id = kho_gui_id,
      nhan_vien_hien_tai_id = v_nv.id,
      ngay_lay_hang = NOW(),
      ngay_cap_nhat = NOW()
  WHERE id = p_don_hang_id;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id, don_hang_id, khach_hang_id, hanh_dong,
    trang_thai_cu, trang_thai_moi, minh_chung, ghi_chu,
    vi_do, kinh_do, thoi_gian
  ) VALUES (
    v_nv.id, v_don.id, v_don.khach_hang_id,
    'Nhân viên lấy hàng đã nhận kiện và chụp minh chứng',
    v_don.trang_thai, 'DA_LAY_HANG', BTRIM(p_minh_chung),
    'Khoảng cách xác nhận: ' || ROUND(v_khoang_cach_met) || ' m',
    p_vi_do, p_kinh_do, NOW()
  );

  RETURN 'DA_LAY_HANG';
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_lay_hang_xac_nhan_minh_chung(
  BIGINT,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,DOUBLE PRECISION,DOUBLE PRECISION
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_lay_hang_xac_nhan_minh_chung(
  BIGINT,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,DOUBLE PRECISION,DOUBLE PRECISION
) TO authenticated;
NOTIFY pgrst, 'reload schema';

