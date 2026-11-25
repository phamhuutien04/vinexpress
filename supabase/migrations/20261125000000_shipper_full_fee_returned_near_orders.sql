-- Đơn giao gần bằng xe máy: shipper đã mang hàng tới người nhận rồi trả lại
-- cho người gửi vẫn được chia phí theo đúng tỷ lệ sàn/shipper đang cấu hình.
CREATE OR REPLACE FUNCTION public.shipper_xac_nhan_hoan_hang(
  p_don_hang_id BIGINT,
  p_minh_chung TEXT,
  p_vi_do DOUBLE PRECISION DEFAULT NULL,
  p_kinh_do DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nv_id BIGINT;
  v_don public.don_hang%ROWTYPE;
  v_khoang_cach_met DOUBLE PRECISION;
  v_phi_hoan_hang NUMERIC;
  v_phan_tram_san NUMERIC;
  v_tien_san NUMERIC;
  v_tien_shipper NUMERIC;
BEGIN
  SELECT nv.id INTO v_nv_id
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id = auth.uid()
    AND nv.vai_tro = 'SHIPPER'
    AND nv.trang_thai = 'HOAT_DONG'
    AND nv.trang_thai_duyet = 'DA_DUYET';

  SELECT dh.* INTO v_don
  FROM public.don_hang dh
  WHERE dh.id = p_don_hang_id
  FOR UPDATE;

  IF v_nv_id IS NULL OR NOT FOUND
     OR v_don.nhan_vien_hien_tai_id IS DISTINCT FROM v_nv_id THEN
    RAISE EXCEPTION 'Bạn không được phân công hoàn đơn hàng này';
  END IF;
  IF v_don.phuong_tien <> 'XE_MAY' OR v_don.trang_thai <> 'GIAO_HANG_THAT_BAI' THEN
    RAISE EXCEPTION 'Đơn hàng chưa được ghi nhận giao thất bại';
  END IF;
  IF NULLIF(BTRIM(p_minh_chung), '') IS NULL THEN
    RAISE EXCEPTION 'Phải có ảnh minh chứng người gửi đã nhận lại kiện hàng';
  END IF;
  IF p_vi_do IS NULL OR p_kinh_do IS NULL
     OR v_don.nguoi_gui_vi_do IS NULL OR v_don.nguoi_gui_kinh_do IS NULL THEN
    RAISE EXCEPTION 'Thiếu tọa độ để xác minh vị trí hoàn hàng';
  END IF;

  v_khoang_cach_met := 6371000 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(v_don.nguoi_gui_vi_do - p_vi_do) / 2), 2)
    + COS(RADIANS(p_vi_do)) * COS(RADIANS(v_don.nguoi_gui_vi_do))
    * POWER(SIN(RADIANS(v_don.nguoi_gui_kinh_do - p_kinh_do) / 2), 2)
  ));
  IF v_khoang_cach_met > 500 THEN
    RAISE EXCEPTION 'Chỉ được xác nhận hoàn hàng trong phạm vi 500 m. Hiện cách % m',
      ROUND(v_khoang_cach_met);
  END IF;

  UPDATE public.don_hang
  SET trang_thai = 'HOAN_HANG', nhan_vien_hien_tai_id = NULL, ngay_cap_nhat = NOW()
  WHERE id = v_don.id;

  v_phi_hoan_hang := GREATEST(COALESCE(v_don.phi_van_chuyen, 0), 0);
  IF v_phi_hoan_hang > 0 THEN
    SELECT COALESCE(pvc.phan_tram_san, 20) INTO v_phan_tram_san
    FROM public.phi_van_chuyen pvc WHERE pvc.id = 1;
    v_tien_san := ROUND(v_phi_hoan_hang * v_phan_tram_san / 100, 0);
    v_tien_shipper := v_phi_hoan_hang - v_tien_san;
    INSERT INTO public.luong_shipper(
      nhan_vien_id, don_hang_id, phi_van_chuyen,
      phan_tram_san, tien_san, tien_shipper, trang_thai, ngay_thanh_toan
    ) VALUES (
      v_nv_id, v_don.id, v_phi_hoan_hang,
      v_phan_tram_san, v_tien_san, v_tien_shipper, 'DA_THANH_TOAN', NOW()
    ) ON CONFLICT (don_hang_id) DO NOTHING;
    PERFORM public.cong_thu_nhap_vi_shipper(v_nv_id, v_don.id, v_tien_shipper);
  END IF;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id, don_hang_id, khach_hang_id, hanh_dong,
    trang_thai_cu, trang_thai_moi, minh_chung, ghi_chu,
    vi_do, kinh_do, thoi_gian
  ) VALUES (
    v_nv_id, v_don.id, v_don.khach_hang_id,
    'Shipper đã hoàn kiện hàng cho người gửi',
    v_don.trang_thai, 'HOAN_HANG', BTRIM(p_minh_chung),
    'Khoảng cách xác nhận: ' || ROUND(v_khoang_cach_met)
      || ' m. Chia phí: sàn ' || ROUND(v_tien_san) || 'đ, shipper '
      || ROUND(v_tien_shipper) || 'đ',
    p_vi_do, p_kinh_do, NOW()
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
