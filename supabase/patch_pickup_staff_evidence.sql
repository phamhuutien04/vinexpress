-- VINEXPRESS - Nhân viên lấy hàng chụp minh chứng trong bán kính 500 m.
-- Bản vá an toàn: không xóa bảng, không xóa dữ liệu.

ALTER TABLE public.giao_dich_vi
  DROP CONSTRAINT IF EXISTS chk_giao_dich_vi_loai;
ALTER TABLE public.giao_dich_vi
  ADD CONSTRAINT chk_giao_dich_vi_loai CHECK (loai IN (
    'NAP_TIEN','RUT_TIEN','YEU_CAU_RUT','HOAN_RUT',
    'TRU_COD','NHAN_COD','HOAN_COD','THU_NHAP_GIAO_HANG',
    'TRU_PHI_LAY_HANG','DIEU_CHINH'
  ));

CREATE OR REPLACE FUNCTION public.kiem_tra_vi_nhan_vien_lay_hang(
  p_don_hang_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_nv_id BIGINT;
  v_cod NUMERIC;
  v_phi NUMERIC;
  v_so_du NUMERIC;
  v_can_doi_soat NUMERIC;
BEGIN
  SELECT nv.id INTO v_nv_id
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id = auth.uid()
    AND nv.vai_tro = 'NHAN_VIEN_LAY_HANG'
    AND nv.trang_thai_duyet = 'DA_DUYET'
    AND nv.trang_thai = 'HOAT_DONG';
  IF v_nv_id IS NULL THEN
    RAISE EXCEPTION 'Tài khoản không phải nhân viên lấy hàng đang hoạt động';
  END IF;

  SELECT dh.cod, dh.phi_van_chuyen INTO v_cod, v_phi
  FROM public.don_hang dh
  WHERE dh.id = p_don_hang_id
    AND dh.nhan_vien_lay_hang_id = v_nv_id
    AND dh.trang_thai = 'CHO_LAY_HANG';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Đơn hàng không thuộc nhân viên hoặc không còn chờ lấy';
  END IF;

  v_can_doi_soat := CASE WHEN COALESCE(v_cod,0) <= 0
    THEN COALESCE(v_phi,0) ELSE 0 END;
  SELECT COALESCE(v.so_du,0) INTO v_so_du
  FROM public.vi v WHERE v.nhan_vien_id = v_nv_id;
  v_so_du := COALESCE(v_so_du,0);

  RETURN jsonb_build_object(
    'so_tien_can_doi_soat', v_can_doi_soat,
    'so_du', v_so_du,
    'du_tien', v_so_du >= v_can_doi_soat
  );
END;
$$;
REVOKE ALL ON FUNCTION public.kiem_tra_vi_nhan_vien_lay_hang(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiem_tra_vi_nhan_vien_lay_hang(BIGINT) TO authenticated;

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
  v_vi_id BIGINT;
  v_so_du NUMERIC;
  v_phi_thu_tien_mat NUMERIC;
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

  -- Đơn không COD: người gửi trả phí vận chuyển tiền mặt cho nhân viên lấy hàng.
  -- Khấu trừ ví nhân viên để đối soát khoản tiền mặt đã thu.
  v_phi_thu_tien_mat := CASE
    WHEN COALESCE(v_don.cod, 0) <= 0 THEN COALESCE(v_don.phi_van_chuyen, 0)
    ELSE 0
  END;
  IF v_phi_thu_tien_mat > 0 THEN
    INSERT INTO public.vi(nhan_vien_id)
    VALUES (v_nv.id)
    ON CONFLICT (nhan_vien_id) DO UPDATE
      SET nhan_vien_id = EXCLUDED.nhan_vien_id
    RETURNING id, so_du INTO v_vi_id, v_so_du;

    IF NOT EXISTS (
      SELECT 1 FROM public.giao_dich_vi gd
      WHERE gd.vi_id = v_vi_id
        AND gd.don_hang_id = v_don.id
        AND gd.loai = 'TRU_PHI_LAY_HANG'
    ) THEN
      IF v_so_du < v_phi_thu_tien_mat THEN
        RAISE EXCEPTION
          'Ví không đủ để đối soát phí lấy hàng. Cần %đ, số dư %đ. Vui lòng nạp ví',
          ROUND(v_phi_thu_tien_mat), ROUND(v_so_du);
      END IF;
      UPDATE public.vi
      SET so_du = so_du - v_phi_thu_tien_mat, ngay_cap_nhat = NOW()
      WHERE id = v_vi_id
      RETURNING so_du INTO v_so_du;
      INSERT INTO public.giao_dich_vi(
        vi_id, don_hang_id, loai, so_tien, so_du_sau, noi_dung
      ) VALUES (
        v_vi_id, v_don.id, 'TRU_PHI_LAY_HANG',
        v_phi_thu_tien_mat, v_so_du,
        'Đối soát phí vận chuyển tiền mặt đã thu từ người gửi'
      );
    END IF;
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
