-- Một kiện chỉ được quét một lần cho mỗi thao tác tại cùng kho/chuyến xe.

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_nhap_kien(p_ma TEXT)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
  v_don public.don_hang%ROWTYPE;
  v_trang_thai_moi VARCHAR;
BEGIN
  SELECT nv.* INTO v_nv
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id = auth.uid()
    AND nv.vai_tro = 'NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet = 'DA_DUYET'
    AND nv.trang_thai = 'HOAT_DONG';
  IF NOT FOUND OR v_nv.kho_hang_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;

  SELECT dh.* INTO v_don
  FROM public.don_hang dh
  WHERE dh.ma_qr::TEXT = BTRIM(p_ma)
     OR UPPER(dh.ma_van_don) = UPPER(BTRIM(p_ma))
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kiện hàng'; END IF;
  IF v_don.kho_gui_id <> v_nv.kho_hang_id
     AND v_don.kho_dich_id <> v_nv.kho_hang_id THEN
    RAISE EXCEPTION 'Kiện hàng không thuộc tuyến của kho này';
  END IF;
  IF v_don.kho_hien_tai_id = v_nv.kho_hang_id
     AND v_don.trang_thai IN ('DEN_KHO_TRUNG_CHUYEN', 'DEN_KHO_DICH') THEN
    RAISE EXCEPTION 'Kiện hàng đã được quét nhập tại kho này';
  END IF;
  IF v_don.trang_thai NOT IN ('DA_LAY_HANG','DANG_VAN_CHUYEN','DEN_KHO_TRUNG_CHUYEN') THEN
    RAISE EXCEPTION 'Trạng thái kiện hàng không cho phép nhập kho';
  END IF;

  v_trang_thai_moi := CASE
    WHEN v_don.kho_dich_id = v_nv.kho_hang_id THEN 'DEN_KHO_DICH'
    ELSE 'DEN_KHO_TRUNG_CHUYEN'
  END;

  UPDATE public.don_hang SET
    kho_hien_tai_id = v_nv.kho_hang_id,
    nhan_vien_hien_tai_id = v_nv.id,
    trang_thai = v_trang_thai_moi,
    ngay_cap_nhat = NOW()
  WHERE id = v_don.id;

  INSERT INTO public.nhat_ky_don_hang (
    nhan_vien_id, don_hang_id, khach_hang_id, hanh_dong,
    trang_thai_cu, trang_thai_moi, kho_id, ghi_chu
  ) VALUES (
    v_nv.id, v_don.id, v_don.khach_hang_id,
    'Nhân viên kho đã quét nhập kiện',
    v_don.trang_thai, v_trang_thai_moi, v_nv.kho_hang_id,
    'Kiện được tiếp nhận vào kho'
  );
  RETURN 'DA_NHAP_KHO';
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_quet_kien_chuyen(
  p_chuyen_xe_id BIGINT,
  p_ma TEXT,
  p_thao_tac TEXT
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
  v_don public.don_hang%ROWTYPE;
  v_chang public.chuyen_xe_chang%ROWTYPE;
  v_thao_tac TEXT;
  v_trang_thai VARCHAR;
  v_ma_chuyen VARCHAR;
  v_trang_thai_moi VARCHAR;
  v_hanh_dong TEXT;
  v_ghi_chu TEXT;
BEGIN
  SELECT nv.* INTO v_nv FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF NOT FOUND OR v_nv.kho_hang_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;
  SELECT c.* INTO v_chang FROM public.chuyen_xe_chang c
  WHERE c.chuyen_xe_id=p_chuyen_xe_id AND c.thu_tu_chuyen=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy chuyến xe'; END IF;
  SELECT ma_chuyen INTO v_ma_chuyen FROM public.chuyen_xe WHERE id=p_chuyen_xe_id;
  SELECT dh.* INTO v_don FROM public.don_hang dh
  WHERE dh.ma_qr::TEXT=BTRIM(p_ma) OR UPPER(dh.ma_van_don)=UPPER(BTRIM(p_ma))
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kiện hàng'; END IF;

  v_thao_tac := UPPER(BTRIM(p_thao_tac));
  IF v_thao_tac='XEP_LEN_XE' THEN
    IF v_chang.kho_di_id<>v_nv.kho_hang_id THEN
      RAISE EXCEPTION 'Chuyến xe không xuất phát từ kho của bạn';
    END IF;
    IF v_don.kho_hien_tai_id IS DISTINCT FROM v_nv.kho_hang_id THEN
      RAISE EXCEPTION 'Kiện hàng chưa có trong kho này';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.chi_tiet_chuyen_xe ct
      WHERE ct.chuyen_xe_id=p_chuyen_xe_id
        AND ct.don_hang_id=v_don.id
        AND ct.trang_thai='DA_XEP_HANG'
    ) THEN
      RAISE EXCEPTION 'Kiện hàng đã được quét xếp lên chuyến xe này';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.chi_tiet_chuyen_xe ct
      JOIN public.chuyen_xe cx ON cx.id=ct.chuyen_xe_id
      WHERE ct.don_hang_id=v_don.id AND cx.id<>p_chuyen_xe_id
        AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')
    ) THEN
      RAISE EXCEPTION 'Kiện hàng đã thuộc chuyến xe khác';
    END IF;
    INSERT INTO public.chi_tiet_chuyen_xe(chuyen_xe_id,don_hang_id,trang_thai)
    VALUES(p_chuyen_xe_id,v_don.id,'DA_XEP_HANG')
    ON CONFLICT(chuyen_xe_id,don_hang_id) DO UPDATE
      SET trang_thai='DA_XEP_HANG',ngay_xep_hang=NOW(),ngay_do_hang=NULL;
    UPDATE public.chuyen_xe SET trang_thai='DANG_XEP_HANG'
    WHERE id=p_chuyen_xe_id AND trang_thai='CHO_KHOI_HANH';
    v_trang_thai := 'DA_XEP_HANG';
    v_trang_thai_moi := v_don.trang_thai;
    v_hanh_dong := 'Nhân viên kho đã quét xếp kiện lên xe';
    v_ghi_chu := 'Đã xếp kiện vào chuyến ' || COALESCE(v_ma_chuyen, '#' || p_chuyen_xe_id::TEXT);
  ELSIF v_thao_tac='NHAP_KHO' THEN
    IF v_chang.kho_den_id<>v_nv.kho_hang_id THEN
      RAISE EXCEPTION 'Chuyến xe không đến kho của bạn';
    END IF;
    IF EXISTS (SELECT 1 FROM public.niem_phong_xe np
      WHERE np.chuyen_xe_id=p_chuyen_xe_id AND np.trang_thai='DA_NIEM_PHONG') THEN
      RAISE EXCEPTION 'Hãy mở niêm phong xe trước khi quét dỡ kiện';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.chi_tiet_chuyen_xe ct
      WHERE ct.chuyen_xe_id=p_chuyen_xe_id AND ct.don_hang_id=v_don.id) THEN
      RAISE EXCEPTION 'Kiện hàng không thuộc chuyến xe này';
    END IF;
    IF EXISTS (SELECT 1 FROM public.chi_tiet_chuyen_xe ct
      WHERE ct.chuyen_xe_id=p_chuyen_xe_id AND ct.don_hang_id=v_don.id
        AND ct.trang_thai='DA_DO_HANG') THEN
      RAISE EXCEPTION 'Kiện hàng đã được quét dỡ tại kho này';
    END IF;
    UPDATE public.chi_tiet_chuyen_xe SET trang_thai='DA_DO_HANG',ngay_do_hang=NOW()
    WHERE chuyen_xe_id=p_chuyen_xe_id AND don_hang_id=v_don.id;
    v_trang_thai_moi := CASE WHEN v_don.kho_dich_id=v_nv.kho_hang_id
      THEN 'DEN_KHO_DICH' ELSE 'DEN_KHO_TRUNG_CHUYEN' END;
    UPDATE public.don_hang SET kho_hien_tai_id=v_nv.kho_hang_id,
      nhan_vien_hien_tai_id=v_nv.id,trang_thai=v_trang_thai_moi,
      ngay_cap_nhat=NOW() WHERE id=v_don.id;
    v_trang_thai := 'DA_NHAP_KHO';
    v_hanh_dong := 'Nhân viên kho đã quét dỡ kiện từ xe';
    v_ghi_chu := 'Đã dỡ kiện từ chuyến ' || COALESCE(v_ma_chuyen, '#' || p_chuyen_xe_id::TEXT);
  ELSE
    RAISE EXCEPTION 'Thao tác quét không hợp lệ';
  END IF;

  INSERT INTO public.nhat_ky_don_hang(
    nhan_vien_id,don_hang_id,khach_hang_id,hanh_dong,
    trang_thai_cu,trang_thai_moi,kho_id,ghi_chu
  ) VALUES (
    v_nv.id,v_don.id,v_don.khach_hang_id,v_hanh_dong,
    v_don.trang_thai,v_trang_thai_moi,v_nv.kho_hang_id,v_ghi_chu
  );
  RETURN v_trang_thai;
END;
$$;

GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_nhap_kien(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_quet_kien_chuyen(BIGINT,TEXT,TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
