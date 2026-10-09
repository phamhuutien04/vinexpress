-- VINEXPRESS - Luồng giao thất bại và hoàn hàng cho đơn giao gần bằng xe máy.
-- Bắt buộc hai minh chứng: một tại người nhận và một khi trả lại người gửi.

CREATE OR REPLACE FUNCTION public.shipper_bao_khong_nhan_duoc_hang(
  p_don_hang_id BIGINT,
  p_ly_do TEXT,
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
    RAISE EXCEPTION 'Bạn không được phân công lấy đơn hàng này';
  END IF;
  IF v_don.phuong_tien <> 'XE_MAY' OR v_don.trang_thai <> 'CHO_LAY_HANG' THEN
    RAISE EXCEPTION 'Đơn hàng không còn ở chặng chờ lấy hàng gần';
  END IF;
  IF NULLIF(BTRIM(p_ly_do), '') IS NULL THEN
    RAISE EXCEPTION 'Phải nhập lý do không nhận được hàng';
  END IF;
  IF NULLIF(BTRIM(p_minh_chung), '') IS NULL THEN
    RAISE EXCEPTION 'Phải có ảnh minh chứng tại điểm lấy hàng';
  END IF;
  IF p_vi_do IS NULL OR p_kinh_do IS NULL
     OR v_don.nguoi_gui_vi_do IS NULL OR v_don.nguoi_gui_kinh_do IS NULL THEN
    RAISE EXCEPTION 'Thiếu tọa độ để xác minh điểm lấy hàng';
  END IF;

  v_khoang_cach_met := 6371000 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(v_don.nguoi_gui_vi_do - p_vi_do) / 2), 2)
    + COS(RADIANS(p_vi_do)) * COS(RADIANS(v_don.nguoi_gui_vi_do))
    * POWER(SIN(RADIANS(v_don.nguoi_gui_kinh_do - p_kinh_do) / 2), 2)
  ));
  IF v_khoang_cach_met > 500 THEN
    RAISE EXCEPTION 'Chỉ được báo không nhận được hàng trong phạm vi 500 m. Hiện cách % m',
      ROUND(v_khoang_cach_met);
  END IF;

  UPDATE public.don_hang
  SET trang_thai = 'DA_HUY',
      nhan_vien_hien_tai_id = NULL,
      ngay_cap_nhat = NOW()
  WHERE id = v_don.id;

  UPDATE public.loi_moi_don_hang_shipper
  SET trang_thai = 'HET_HAN', phan_hoi_luc = NOW()
  WHERE don_hang_id = v_don.id
    AND nhan_vien_id = v_nv_id;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id, don_hang_id, khach_hang_id, hanh_dong,
    trang_thai_cu, trang_thai_moi, minh_chung, ghi_chu,
    vi_do, kinh_do, thoi_gian
  ) VALUES (
    v_nv_id, v_don.id, v_don.khach_hang_id,
    'Shipper không nhận được kiện hàng từ người gửi',
    v_don.trang_thai, 'DA_HUY', BTRIM(p_minh_chung),
    BTRIM(p_ly_do) || '. Khoảng cách xác nhận: ' ||
      ROUND(v_khoang_cach_met) || ' m',
    p_vi_do, p_kinh_do, NOW()
  );

  -- Chưa nhận kiện nên không thu tiền, không trừ ví và không cộng thu nhập.
END;
$$;

CREATE OR REPLACE FUNCTION public.shipper_bao_giao_that_bai(
  p_don_hang_id BIGINT,
  p_ly_do TEXT,
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
    RAISE EXCEPTION 'Bạn không được phân công giao đơn hàng này';
  END IF;
  IF v_don.phuong_tien <> 'XE_MAY' THEN
    RAISE EXCEPTION 'Chức năng hoàn trực tiếp chỉ áp dụng cho đơn giao gần bằng xe máy';
  END IF;
  IF v_don.trang_thai NOT IN ('DA_LAY_HANG', 'DANG_GIAO_HANG') THEN
    RAISE EXCEPTION 'Đơn hàng không ở trạng thái đang giao';
  END IF;
  IF NULLIF(BTRIM(p_ly_do), '') IS NULL THEN
    RAISE EXCEPTION 'Phải chọn lý do giao hàng thất bại';
  END IF;
  IF NULLIF(BTRIM(p_minh_chung), '') IS NULL THEN
    RAISE EXCEPTION 'Phải có ảnh minh chứng giao hàng thất bại';
  END IF;
  IF p_vi_do IS NULL OR p_kinh_do IS NULL
     OR v_don.nguoi_nhan_vi_do IS NULL OR v_don.nguoi_nhan_kinh_do IS NULL THEN
    RAISE EXCEPTION 'Thiếu tọa độ để xác minh vị trí giao thất bại';
  END IF;

  v_khoang_cach_met := 6371000 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(v_don.nguoi_nhan_vi_do - p_vi_do) / 2), 2)
    + COS(RADIANS(p_vi_do)) * COS(RADIANS(v_don.nguoi_nhan_vi_do))
    * POWER(SIN(RADIANS(v_don.nguoi_nhan_kinh_do - p_kinh_do) / 2), 2)
  ));
  IF v_khoang_cach_met > 500 THEN
    RAISE EXCEPTION 'Chỉ được báo giao thất bại trong phạm vi 500 m. Hiện cách % m',
      ROUND(v_khoang_cach_met);
  END IF;

  UPDATE public.don_hang
  SET trang_thai = 'GIAO_HANG_THAT_BAI',
      ngay_cap_nhat = NOW()
  WHERE id = v_don.id;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id, don_hang_id, khach_hang_id, hanh_dong,
    trang_thai_cu, trang_thai_moi, minh_chung, ghi_chu,
    vi_do, kinh_do, thoi_gian
  ) VALUES (
    v_nv_id, v_don.id, v_don.khach_hang_id,
    'Shipper báo giao hàng thất bại và bắt đầu hoàn về người gửi',
    v_don.trang_thai, 'GIAO_HANG_THAT_BAI', BTRIM(p_minh_chung),
    BTRIM(p_ly_do) || '. Khoảng cách xác nhận: ' ||
      ROUND(v_khoang_cach_met) || ' m',
    p_vi_do, p_kinh_do, NOW()
  );

  -- Không gọi tam_giu_cod_vi_shipper và không cộng thu nhập ở bước này.
END;
$$;

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
  IF v_don.trang_thai <> 'GIAO_HANG_THAT_BAI' THEN
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
  SET trang_thai = 'HOAN_HANG',
      nhan_vien_hien_tai_id = NULL,
      ngay_cap_nhat = NOW()
  WHERE id = v_don.id;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id, don_hang_id, khach_hang_id, hanh_dong,
    trang_thai_cu, trang_thai_moi, minh_chung, ghi_chu,
    vi_do, kinh_do, thoi_gian
  ) VALUES (
    v_nv_id, v_don.id, v_don.khach_hang_id,
    'Shipper đã hoàn kiện hàng cho người gửi',
    v_don.trang_thai, 'HOAN_HANG', BTRIM(p_minh_chung),
    'Khoảng cách xác nhận: ' || ROUND(v_khoang_cach_met) || ' m',
    p_vi_do, p_kinh_do, NOW()
  );

  -- Không trừ COD và không cộng thu nhập giao hàng cho đơn hoàn.
END;
$$;

CREATE OR REPLACE FUNCTION public.don_hang_dang_giao_cua_shipper()
RETURNS TABLE (
  id BIGINT, ma_van_don VARCHAR, trang_thai VARCHAR,
  nguoi_gui_ten VARCHAR, nguoi_gui_sdt VARCHAR, nguoi_gui_dia_chi TEXT,
  nguoi_nhan_ten VARCHAR, nguoi_nhan_sdt VARCHAR, nguoi_nhan_dia_chi TEXT,
  nguoi_gui_vi_do DOUBLE PRECISION, nguoi_gui_kinh_do DOUBLE PRECISION,
  nguoi_nhan_vi_do DOUBLE PRECISION, nguoi_nhan_kinh_do DOUBLE PRECISION,
  can_nang NUMERIC, cod NUMERIC, phi_van_chuyen NUMERIC,
  tien_shipper_du_kien NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    dh.id, dh.ma_van_don, dh.trang_thai,
    dh.nguoi_gui_ten, dh.nguoi_gui_sdt, dh.nguoi_gui_dia_chi,
    dh.nguoi_nhan_ten, dh.nguoi_nhan_sdt, dh.nguoi_nhan_dia_chi,
    dh.nguoi_gui_vi_do, dh.nguoi_gui_kinh_do,
    dh.nguoi_nhan_vi_do, dh.nguoi_nhan_kinh_do,
    dh.can_nang, dh.cod, dh.phi_van_chuyen,
    ROUND(
      dh.phi_van_chuyen *
      (100 - COALESCE((SELECT pvc.phan_tram_san
                       FROM public.phi_van_chuyen pvc WHERE pvc.id = 1), 20)) / 100,
      0
    )
  FROM public.don_hang dh
  JOIN public.nhan_vien nv ON nv.id = dh.nhan_vien_hien_tai_id
  WHERE nv.auth_user_id = auth.uid()
    AND dh.trang_thai IN (
      'CHO_LAY_HANG', 'DA_LAY_HANG', 'GIAO_CHO_SHIPPER',
      'DANG_GIAO_HANG', 'GIAO_HANG_THAT_BAI'
    )
  ORDER BY dh.ngay_tao DESC;
$$;

REVOKE ALL ON FUNCTION public.shipper_bao_giao_that_bai(
  BIGINT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.shipper_bao_khong_nhan_duoc_hang(
  BIGINT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.shipper_xac_nhan_hoan_hang(
  BIGINT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.shipper_bao_giao_that_bai(
  BIGINT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shipper_bao_khong_nhan_duoc_hang(
  BIGINT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shipper_xac_nhan_hoan_hang(
  BIGINT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;

NOTIFY pgrst, 'reload schema';
