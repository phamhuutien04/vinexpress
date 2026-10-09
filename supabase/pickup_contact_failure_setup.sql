-- VINEXPRESS - Nhân viên lấy hàng báo không liên lạc được người gửi.
-- Đơn vẫn CHO_LAY_HANG và vẫn thuộc nhân viên để có thể hẹn lấy lại.
-- Hàm không thu tiền, không tạo giao dịch ví và không khấu trừ số dư.

CREATE OR REPLACE FUNCTION public.nhan_vien_lay_hang_bao_khong_lien_lac(
  p_don_hang_id BIGINT,
  p_minh_chung TEXT,
  p_ghi_chu TEXT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
  v_don public.don_hang%ROWTYPE;
  v_ghi_chu TEXT;
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

  IF NOT FOUND
     OR v_don.nhan_vien_lay_hang_id IS DISTINCT FROM v_nv.id
     OR v_don.trang_thai <> 'CHO_LAY_HANG' THEN
    RAISE EXCEPTION 'Đơn hàng không thuộc nhân viên hoặc không còn chờ lấy';
  END IF;

  IF p_minh_chung IS NULL OR BTRIM(p_minh_chung) = '' THEN
    RAISE EXCEPTION 'Phải có ảnh minh chứng không liên lạc được người gửi';
  END IF;

  v_ghi_chu := 'Không liên lạc được người gửi';
  IF NULLIF(BTRIM(p_ghi_chu), '') IS NOT NULL THEN
    v_ghi_chu := v_ghi_chu || ': ' || BTRIM(p_ghi_chu);
  END IF;

  -- Không thay đổi trạng thái và không đụng tới ví. Nhân viên có thể thử lấy lại.
  UPDATE public.don_hang
  SET ngay_cap_nhat = NOW()
  WHERE id = v_don.id;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id,
    don_hang_id,
    khach_hang_id,
    hanh_dong,
    trang_thai_cu,
    trang_thai_moi,
    minh_chung,
    ghi_chu,
    thoi_gian
  ) VALUES (
    v_nv.id,
    v_don.id,
    v_don.khach_hang_id,
    'Nhân viên lấy hàng báo không liên lạc được người gửi',
    v_don.trang_thai,
    v_don.trang_thai,
    BTRIM(p_minh_chung),
    v_ghi_chu,
    NOW()
  );

  RETURN 'CHO_LAY_HANG';
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_lay_hang_bao_khong_lien_lac(
  BIGINT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_lay_hang_bao_khong_lien_lac(
  BIGINT, TEXT, TEXT
) TO authenticated;

NOTIFY pgrst, 'reload schema';
