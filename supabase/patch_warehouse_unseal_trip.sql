-- Cho nhân viên kho đến mở niêm phong trước khi dỡ kiện khỏi xe.
-- Chạy an toàn nhiều lần trong Supabase SQL Editor, không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_mo_niem_phong_chuyen(
  p_chuyen_xe_id BIGINT,
  p_ma_niem_phong TEXT
) RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_nhan_vien public.nhan_vien%ROWTYPE;
  v_niem_phong public.niem_phong_xe%ROWTYPE;
  v_ma TEXT := UPPER(BTRIM(COALESCE(p_ma_niem_phong,'')));
  v_trang_thai_chuyen VARCHAR;
BEGIN
  SELECT nv.* INTO v_nhan_vien
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF NOT FOUND OR v_nhan_vien.kho_hang_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;
  IF v_ma='' THEN
    RAISE EXCEPTION 'Hãy nhập mã niêm phong trên xe';
  END IF;

  SELECT cx.trang_thai INTO v_trang_thai_chuyen
  FROM public.chuyen_xe cx
  JOIN public.chuyen_xe_chang c
    ON c.chuyen_xe_id=cx.id AND c.thu_tu_chuyen=1
  WHERE cx.id=p_chuyen_xe_id
    AND c.kho_den_id=v_nhan_vien.kho_hang_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chuyến xe không đến kho của bạn';
  END IF;
  IF v_trang_thai_chuyen<>'DA_DEN' THEN
    RAISE EXCEPTION 'Tài xế phải xác nhận đã đến kho trước khi mở niêm phong';
  END IF;

  SELECT np.* INTO v_niem_phong
  FROM public.niem_phong_xe np
  WHERE np.chuyen_xe_id=p_chuyen_xe_id
    AND np.trang_thai='DA_NIEM_PHONG'
  ORDER BY np.thoi_gian_niem_phong DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    IF EXISTS(
      SELECT 1 FROM public.niem_phong_xe np
      WHERE np.chuyen_xe_id=p_chuyen_xe_id AND np.trang_thai='DA_MO'
    ) THEN
      RAISE EXCEPTION 'Niêm phong của chuyến đã được mở';
    END IF;
    RAISE EXCEPTION 'Không tìm thấy niêm phong đang đóng của chuyến';
  END IF;
  IF UPPER(BTRIM(v_niem_phong.ma_niem_phong))<>v_ma THEN
    RAISE EXCEPTION 'Mã niêm phong không khớp với mã đã ghi nhận';
  END IF;

  UPDATE public.niem_phong_xe
  SET trang_thai='DA_MO',
      kho_mo_niem_phong_id=v_nhan_vien.kho_hang_id,
      nguoi_mo_id=v_nhan_vien.id,
      thoi_gian_mo=NOW()
  WHERE id=v_niem_phong.id;

  RETURN v_niem_phong.ma_niem_phong;
END;
$$;

-- Không cho dỡ kiện khi dây niêm phong của chuyến vẫn đang đóng.
CREATE OR REPLACE FUNCTION public.nhan_vien_kho_quet_kien_chuyen(
  p_chuyen_xe_id BIGINT,p_ma TEXT,p_thao_tac TEXT
) RETURNS VARCHAR LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE; v_don public.don_hang%ROWTYPE;
  v_chang public.chuyen_xe_chang%ROWTYPE; v_thao_tac TEXT; v_trang_thai VARCHAR;
BEGIN
  SELECT nv.* INTO v_nv FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF NOT FOUND OR v_nv.kho_hang_id IS NULL THEN RAISE EXCEPTION 'Nhân viên chưa được gán kho'; END IF;
  SELECT c.* INTO v_chang FROM public.chuyen_xe_chang c
  WHERE c.chuyen_xe_id=p_chuyen_xe_id AND c.thu_tu_chuyen=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy chuyến xe'; END IF;
  SELECT dh.* INTO v_don FROM public.don_hang dh
  WHERE dh.ma_qr::TEXT=BTRIM(p_ma) OR UPPER(dh.ma_van_don)=UPPER(BTRIM(p_ma)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kiện hàng'; END IF;
  v_thao_tac := UPPER(BTRIM(p_thao_tac));
  IF v_thao_tac='XEP_LEN_XE' THEN
    IF v_chang.kho_di_id<>v_nv.kho_hang_id THEN RAISE EXCEPTION 'Chuyến xe không xuất phát từ kho của bạn'; END IF;
    IF v_don.kho_hien_tai_id IS DISTINCT FROM v_nv.kho_hang_id THEN RAISE EXCEPTION 'Kiện hàng chưa có trong kho này'; END IF;
    IF EXISTS(SELECT 1 FROM public.chi_tiet_chuyen_xe ct JOIN public.chuyen_xe cx ON cx.id=ct.chuyen_xe_id
      WHERE ct.don_hang_id=v_don.id AND cx.id<>p_chuyen_xe_id
        AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')) THEN
      RAISE EXCEPTION 'Kiện hàng đã thuộc chuyến xe khác';
    END IF;
    INSERT INTO public.chi_tiet_chuyen_xe(chuyen_xe_id,don_hang_id,trang_thai)
    VALUES(p_chuyen_xe_id,v_don.id,'DA_XEP_HANG') ON CONFLICT(chuyen_xe_id,don_hang_id)
    DO UPDATE SET trang_thai='DA_XEP_HANG',ngay_xep_hang=NOW(),ngay_do_hang=NULL;
    UPDATE public.chuyen_xe SET trang_thai='DANG_XEP_HANG' WHERE id=p_chuyen_xe_id AND trang_thai='CHO_KHOI_HANH';
    v_trang_thai := 'DA_XEP_HANG';
  ELSIF v_thao_tac='NHAP_KHO' THEN
    IF v_chang.kho_den_id<>v_nv.kho_hang_id THEN RAISE EXCEPTION 'Chuyến xe không đến kho của bạn'; END IF;
    IF EXISTS(
      SELECT 1 FROM public.niem_phong_xe np
      WHERE np.chuyen_xe_id=p_chuyen_xe_id AND np.trang_thai='DA_NIEM_PHONG'
    ) THEN
      RAISE EXCEPTION 'Hãy mở niêm phong xe trước khi quét dỡ kiện';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.chi_tiet_chuyen_xe ct WHERE ct.chuyen_xe_id=p_chuyen_xe_id AND ct.don_hang_id=v_don.id) THEN
      RAISE EXCEPTION 'Kiện hàng không thuộc chuyến xe này';
    END IF;
    UPDATE public.chi_tiet_chuyen_xe SET trang_thai='DA_DO_HANG',ngay_do_hang=NOW()
    WHERE chuyen_xe_id=p_chuyen_xe_id AND don_hang_id=v_don.id;
    UPDATE public.don_hang SET kho_hien_tai_id=v_nv.kho_hang_id,
      nhan_vien_hien_tai_id=v_nv.id,
      trang_thai=CASE WHEN kho_dich_id=v_nv.kho_hang_id THEN 'DEN_KHO_DICH' ELSE 'DEN_KHO_TRUNG_CHUYEN' END,
      ngay_cap_nhat=NOW() WHERE id=v_don.id;
    v_trang_thai := 'DA_NHAP_KHO';
  ELSE RAISE EXCEPTION 'Thao tác quét không hợp lệ';
  END IF;
  RETURN v_trang_thai;
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_kho_mo_niem_phong_chuyen(BIGINT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_mo_niem_phong_chuyen(BIGINT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.nhan_vien_kho_quet_kien_chuyen(BIGINT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_quet_kien_chuyen(BIGINT,TEXT,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
