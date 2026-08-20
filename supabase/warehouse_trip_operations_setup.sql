-- Quan ly kho gan xe/chuyen va nhan vien kho quet kien.
-- Ban nang cap an toan, khong xoa du lieu.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_xe(p_kho_id BIGINT)
RETURNS TABLE(id BIGINT,bien_so_xe VARCHAR,tai_trong NUMERIC,trang_thai VARCHAR,
  tai_xe_id BIGINT,ten_tai_xe VARCHAR,so_dien_thoai VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
    RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
  END IF;
  RETURN QUERY
  SELECT x.id,x.bien_so_xe::VARCHAR,x.tai_trong,x.trang_thai::VARCHAR,
    x.tai_xe_id,nv.ho_ten::VARCHAR,nv.so_dien_thoai::VARCHAR
  FROM public.xe x
  JOIN public.nhan_vien nv ON nv.id=x.tai_xe_id
  WHERE nv.kho_hang_id=p_kho_id AND nv.vai_tro='VAN_CHUYEN'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG'
  ORDER BY CASE x.trang_thai WHEN 'SAN_SANG' THEN 0 ELSE 1 END,x.bien_so_xe;
END;
$$;

-- Danh sách kho đến theo đúng cây vận chuyển:
-- cấp 2 chỉ đi lên kho cấp 1 trực thuộc;
-- cấp 1 đi xuống kho cấp 2 trực thuộc hoặc sang một kho cấp 1 khác.
CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_kho_den(p_kho_di_id BIGINT)
RETURNS TABLE(id BIGINT,ma_kho VARCHAR,ten_kho VARCHAR,dia_chi TEXT,
  cap_kho SMALLINT,kho_trung_tam_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_cap SMALLINT; v_kho_cha BIGINT;
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_di_id) THEN
    RAISE EXCEPTION 'Kho khởi hành không thuộc phạm vi quản lý';
  END IF;
  SELECT kh.cap_kho,kh.kho_trung_tam_id INTO v_cap,v_kho_cha
  FROM public.kho_hang kh WHERE kh.id=p_kho_di_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kho khởi hành'; END IF;

  RETURN QUERY
  SELECT kh.id,kh.ma_kho::VARCHAR,kh.ten_kho::VARCHAR,kh.dia_chi,
    kh.cap_kho,kh.kho_trung_tam_id
  FROM public.kho_hang kh
  WHERE kh.id<>p_kho_di_id
    AND (
      -- Kho cấp 2 luôn nhìn thấy đúng kho cấp 1 cha để có thể gán xe trả hàng về.
      (v_cap=2 AND kh.id=v_kho_cha)
      OR
      (v_cap=1 AND kh.trang_thai='HOAT_DONG' AND (
        (kh.cap_kho=2 AND kh.kho_trung_tam_id=p_kho_di_id)
        OR kh.cap_kho=1
      ))
    )
  ORDER BY kh.cap_kho,kh.ten_kho;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_chuyen(p_kho_id BIGINT)
RETURNS TABLE(id BIGINT,ma_chuyen VARCHAR,trang_thai VARCHAR,xe_id BIGINT,
  bien_so_xe VARCHAR,ten_tai_xe VARCHAR,kho_di_id BIGINT,ten_kho_di VARCHAR,
  kho_den_id BIGINT,ten_kho_den VARCHAR,ngay_du_kien TIMESTAMPTZ,
  so_kien BIGINT)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
    RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
  END IF;
  RETURN QUERY
  SELECT cx.id,cx.ma_chuyen::VARCHAR,cx.trang_thai::VARCHAR,cx.xe_id,
    x.bien_so_xe::VARCHAR,nv.ho_ten::VARCHAR,c.kho_di_id,kd.ten_kho::VARCHAR,
    c.kho_den_id,kn.ten_kho::VARCHAR,cx.ngay_du_kien,
    (SELECT COUNT(*) FROM public.chi_tiet_chuyen_xe ct
      WHERE ct.chuyen_xe_id=cx.id)::BIGINT
  FROM public.chuyen_xe cx
  JOIN public.xe x ON x.id=cx.xe_id
  LEFT JOIN public.nhan_vien nv ON nv.id=x.tai_xe_id
  JOIN public.chuyen_xe_chang c ON c.chuyen_xe_id=cx.id AND c.thu_tu_chuyen=1
  JOIN public.kho_hang kd ON kd.id=c.kho_di_id
  JOIN public.kho_hang kn ON kn.id=c.kho_den_id
  WHERE c.kho_di_id=p_kho_id OR c.kho_den_id=p_kho_id
  ORDER BY cx.ngay_tao DESC LIMIT 200;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(
  p_kho_di_id BIGINT,p_kho_den_id BIGINT,p_xe_id BIGINT,
  p_ngay_du_kien TIMESTAMPTZ DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv_id BIGINT; v_chuyen_id BIGINT; v_ma VARCHAR;
BEGIN
  IF p_kho_di_id=p_kho_den_id THEN RAISE EXCEPTION 'Kho đi và kho đến phải khác nhau'; END IF;
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_di_id) THEN
    RAISE EXCEPTION 'Bạn không quản lý kho khởi hành';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.quan_ly_kho_danh_sach_kho_den(p_kho_di_id) d
    WHERE d.id=p_kho_den_id
  ) THEN
    RAISE EXCEPTION 'Kho đến không đúng tuyến được phép của kho khởi hành';
  END IF;
  SELECT nv.id INTO v_nv_id FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='QUAN_LY_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF v_nv_id IS NULL THEN RAISE EXCEPTION 'Tài khoản không phải quản lý kho'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.xe x JOIN public.nhan_vien tx ON tx.id=x.tai_xe_id
    WHERE x.id=p_xe_id AND x.trang_thai='SAN_SANG'
      AND tx.kho_hang_id=p_kho_di_id AND tx.vai_tro='VAN_CHUYEN'
  ) THEN RAISE EXCEPTION 'Xe không sẵn sàng hoặc không thuộc kho khởi hành'; END IF;
  IF EXISTS(SELECT 1 FROM public.chuyen_xe cx WHERE cx.xe_id=p_xe_id
    AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')) THEN
    RAISE EXCEPTION 'Xe đang có chuyến chưa hoàn thành';
  END IF;
  v_ma := 'CX' || TO_CHAR(NOW(),'YYMMDDHH24MISS') || UPPER(SUBSTR(REPLACE(gen_random_uuid()::TEXT,'-',''),1,5));
  INSERT INTO public.chuyen_xe(xe_id,ma_chuyen,trang_thai,ngay_du_kien)
  VALUES(p_xe_id,v_ma,'CHO_KHOI_HANH',p_ngay_du_kien) RETURNING id INTO v_chuyen_id;
  INSERT INTO public.chuyen_xe_chang(chuyen_xe_id,thu_tu_chuyen,kho_di_id,
    kho_den_id,nguoi_phan_cong_id,ngay_den_du_kien)
  VALUES(v_chuyen_id,1,p_kho_di_id,p_kho_den_id,v_nv_id,p_ngay_du_kien);
  RETURN v_chuyen_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_danh_sach_chuyen()
RETURNS TABLE(id BIGINT,ma_chuyen VARCHAR,trang_thai VARCHAR,bien_so_xe VARCHAR,
  ten_tai_xe VARCHAR,kho_di_id BIGINT,ten_kho_di VARCHAR,kho_den_id BIGINT,
  ten_kho_den VARCHAR,so_kien BIGINT)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_kho_id BIGINT;
BEGIN
  SELECT nv.kho_hang_id INTO v_kho_id FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF v_kho_id IS NULL THEN RAISE EXCEPTION 'Nhân viên chưa được gán kho'; END IF;
  RETURN QUERY
  SELECT cx.id,cx.ma_chuyen::VARCHAR,cx.trang_thai::VARCHAR,x.bien_so_xe::VARCHAR,
    tx.ho_ten::VARCHAR,c.kho_di_id,kd.ten_kho::VARCHAR,c.kho_den_id,
    kn.ten_kho::VARCHAR,(SELECT COUNT(*) FROM public.chi_tiet_chuyen_xe ct
      WHERE ct.chuyen_xe_id=cx.id)::BIGINT
  FROM public.chuyen_xe cx JOIN public.xe x ON x.id=cx.xe_id
  LEFT JOIN public.nhan_vien tx ON tx.id=x.tai_xe_id
  JOIN public.chuyen_xe_chang c ON c.chuyen_xe_id=cx.id AND c.thu_tu_chuyen=1
  JOIN public.kho_hang kd ON kd.id=c.kho_di_id JOIN public.kho_hang kn ON kn.id=c.kho_den_id
  WHERE (c.kho_di_id=v_kho_id AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG'))
     OR (c.kho_den_id=v_kho_id AND cx.trang_thai IN ('DANG_DI','DA_DEN'))
  ORDER BY cx.ngay_tao DESC;
END;
$$;

-- Nhận kiện do nhân viên lấy hàng đưa về kho. Thao tác này không cần chọn chuyến xe.
CREATE OR REPLACE FUNCTION public.nhan_vien_kho_nhap_kien(p_ma TEXT)
RETURNS VARCHAR LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE; v_don public.don_hang%ROWTYPE;
BEGIN
  SELECT nv.* INTO v_nv FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF NOT FOUND OR v_nv.kho_hang_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;

  SELECT dh.* INTO v_don FROM public.don_hang dh
  WHERE dh.ma_qr::TEXT=BTRIM(p_ma) OR UPPER(dh.ma_van_don)=UPPER(BTRIM(p_ma))
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kiện hàng'; END IF;
  IF v_don.kho_gui_id<>v_nv.kho_hang_id AND v_don.kho_dich_id<>v_nv.kho_hang_id THEN
    RAISE EXCEPTION 'Kiện hàng không thuộc tuyến của kho này';
  END IF;
  IF v_don.trang_thai NOT IN ('DA_LAY_HANG','DANG_VAN_CHUYEN','DEN_KHO_TRUNG_CHUYEN') THEN
    RAISE EXCEPTION 'Trạng thái kiện hàng không cho phép nhập kho';
  END IF;

  UPDATE public.don_hang SET
    kho_hien_tai_id=v_nv.kho_hang_id,
    nhan_vien_hien_tai_id=v_nv.id,
    trang_thai=CASE WHEN kho_dich_id=v_nv.kho_hang_id
      THEN 'DEN_KHO_DICH' ELSE 'DEN_KHO_TRUNG_CHUYEN' END,
    ngay_cap_nhat=NOW()
  WHERE id=v_don.id;
  RETURN 'DA_NHAP_KHO';
END;
$$;

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

GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_xe(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_kho_den(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_chuyen(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(BIGINT,BIGINT,BIGINT,TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_danh_sach_chuyen() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_nhap_kien(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_quet_kien_chuyen(BIGINT,TEXT,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';

-- BAN SUA TRUY VAN KHO DEN CAP NHAT
-- Sửa riêng danh sách kho đến, không xóa hay thay đổi dữ liệu kho.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_kho_den(p_kho_di_id BIGINT)
RETURNS TABLE(id BIGINT,ma_kho VARCHAR,ten_kho VARCHAR,dia_chi TEXT,
  cap_kho SMALLINT,kho_trung_tam_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE
  v_kho_quan_ly BIGINT;
  v_cap_quan_ly SMALLINT;
  v_cap_kho_di SMALLINT;
  v_kho_cha BIGINT;
BEGIN
  SELECT nv.kho_hang_id,kh.cap_kho
  INTO v_kho_quan_ly,v_cap_quan_ly
  FROM public.nhan_vien nv
  JOIN public.kho_hang kh ON kh.id=nv.kho_hang_id
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='QUAN_LY_KHO'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF v_kho_quan_ly IS NULL THEN
    RAISE EXCEPTION 'Quản lý chưa được gán kho';
  END IF;

  SELECT kh.cap_kho,kh.kho_trung_tam_id
  INTO v_cap_kho_di,v_kho_cha
  FROM public.kho_hang kh
  WHERE kh.id=p_kho_di_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kho khởi hành'; END IF;

  IF p_kho_di_id<>v_kho_quan_ly AND NOT (
    v_cap_quan_ly=1 AND v_cap_kho_di=2 AND v_kho_cha=v_kho_quan_ly
  ) THEN
    RAISE EXCEPTION 'Kho khởi hành không thuộc phạm vi quản lý';
  END IF;

  IF v_cap_kho_di=2 THEN
    -- An Phú (cấp 2) sẽ trả đúng Kho trung tâm Sài Gòn (cấp 1).
    RETURN QUERY
    SELECT kh.id,kh.ma_kho::VARCHAR,kh.ten_kho::VARCHAR,kh.dia_chi,
      kh.cap_kho,kh.kho_trung_tam_id
    FROM public.kho_hang kh
    WHERE kh.id=v_kho_cha;
  ELSE
    -- Kho cấp 1 đi xuống kho cấp 2 trực thuộc hoặc sang kho cấp 1 khác.
    RETURN QUERY
    SELECT kh.id,kh.ma_kho::VARCHAR,kh.ten_kho::VARCHAR,kh.dia_chi,
      kh.cap_kho,kh.kho_trung_tam_id
    FROM public.kho_hang kh
    WHERE kh.id<>p_kho_di_id AND kh.trang_thai='HOAT_DONG'
      AND (kh.cap_kho=1 OR (kh.cap_kho=2 AND kh.kho_trung_tam_id=p_kho_di_id))
    ORDER BY kh.cap_kho,kh.ten_kho;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_kho_den(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_kho_den(BIGINT) TO authenticated;
NOTIFY pgrst,'reload schema';

-- BAN VA CAP 2 TAO CHUYEN LEN CAP 1
-- Bản sửa tối giản: kho cấp 2 luôn lấy được kho cấp 1 trực thuộc.
-- Không thay đổi dữ liệu và không bỏ kiểm tra quyền khi tạo chuyến.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_kho_den(p_kho_di_id BIGINT)
RETURNS TABLE(id BIGINT,ma_kho VARCHAR,ten_kho VARCHAR,dia_chi TEXT,
  cap_kho SMALLINT,kho_trung_tam_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_cap_kho_di SMALLINT; v_kho_cha BIGINT;
BEGIN
  SELECT kh.cap_kho,kh.kho_trung_tam_id
  INTO v_cap_kho_di,v_kho_cha
  FROM public.kho_hang kh WHERE kh.id=p_kho_di_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kho khởi hành'; END IF;

  IF v_cap_kho_di=2 THEN
    IF v_kho_cha IS NULL THEN
      RAISE EXCEPTION 'Kho cấp 2 chưa được gán kho cấp 1 trực thuộc';
    END IF;
    RETURN QUERY
    SELECT kh.id,kh.ma_kho::VARCHAR,kh.ten_kho::VARCHAR,kh.dia_chi,
      kh.cap_kho,kh.kho_trung_tam_id
    FROM public.kho_hang kh WHERE kh.id=v_kho_cha;
  ELSE
    RETURN QUERY
    SELECT kh.id,kh.ma_kho::VARCHAR,kh.ten_kho::VARCHAR,kh.dia_chi,
      kh.cap_kho,kh.kho_trung_tam_id
    FROM public.kho_hang kh
    WHERE kh.id<>p_kho_di_id AND kh.trang_thai='HOAT_DONG'
      AND (kh.cap_kho=1 OR (kh.cap_kho=2 AND kh.kho_trung_tam_id=p_kho_di_id))
    ORDER BY kh.cap_kho,kh.ten_kho;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_kho_den(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_kho_den(BIGINT) TO authenticated;
NOTIFY pgrst,'reload schema';

-- BAN VA QUAN LY KHO CAP 2 GAN XE
-- Cho quản lý kho cấp 2 gán xe tạo chuyến lên kho cấp 1 trực thuộc.
-- Không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_xe(p_kho_id BIGINT)
RETURNS TABLE(id BIGINT,bien_so_xe VARCHAR,tai_trong NUMERIC,trang_thai VARCHAR,
  tai_xe_id BIGINT,ten_tai_xe VARCHAR,so_dien_thoai VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_cap SMALLINT; v_kho_cha BIGINT;
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
    RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
  END IF;
  SELECT kh.cap_kho,kh.kho_trung_tam_id INTO v_cap,v_kho_cha
  FROM public.kho_hang kh WHERE kh.id=p_kho_id;

  RETURN QUERY
  SELECT x.id,x.bien_so_xe::VARCHAR,x.tai_trong,x.trang_thai::VARCHAR,
    x.tai_xe_id,nv.ho_ten::VARCHAR,nv.so_dien_thoai::VARCHAR
  FROM public.xe x
  JOIN public.nhan_vien nv ON nv.id=x.tai_xe_id
  WHERE (
      nv.kho_hang_id=p_kho_id
      OR (v_cap=2 AND nv.kho_hang_id=v_kho_cha)
    )
    AND nv.vai_tro='VAN_CHUYEN'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG'
    AND NOT EXISTS(
      SELECT 1 FROM public.chuyen_xe cx
      WHERE cx.xe_id=x.id
        AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')
    )
  ORDER BY CASE x.trang_thai WHEN 'SAN_SANG' THEN 0 ELSE 1 END,x.bien_so_xe;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(
  p_kho_di_id BIGINT,p_kho_den_id BIGINT,p_xe_id BIGINT,
  p_ngay_du_kien TIMESTAMPTZ DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv_id BIGINT; v_chuyen_id BIGINT; v_ma VARCHAR;
  v_cap_di SMALLINT; v_kho_cha BIGINT;
BEGIN
  IF p_kho_di_id=p_kho_den_id THEN RAISE EXCEPTION 'Kho đi và kho đến phải khác nhau'; END IF;
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_di_id) THEN
    RAISE EXCEPTION 'Bạn không quản lý kho khởi hành';
  END IF;
  SELECT nv.id INTO v_nv_id FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='QUAN_LY_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF v_nv_id IS NULL THEN RAISE EXCEPTION 'Tài khoản không phải quản lý kho'; END IF;

  SELECT kh.cap_kho,kh.kho_trung_tam_id INTO v_cap_di,v_kho_cha
  FROM public.kho_hang kh WHERE kh.id=p_kho_di_id;
  IF v_cap_di=2 AND p_kho_den_id<>v_kho_cha THEN
    RAISE EXCEPTION 'Kho cấp 2 chỉ được tạo chuyến lên kho cấp 1 trực thuộc';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.quan_ly_kho_danh_sach_kho_den(p_kho_di_id) d
    WHERE d.id=p_kho_den_id
  ) THEN RAISE EXCEPTION 'Kho đến không đúng tuyến được phép'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.xe x
    JOIN public.nhan_vien tx ON tx.id=x.tai_xe_id
    WHERE x.id=p_xe_id AND x.trang_thai='SAN_SANG'
      AND tx.vai_tro='VAN_CHUYEN'
      AND (tx.kho_hang_id=p_kho_di_id OR (v_cap_di=2 AND tx.kho_hang_id=v_kho_cha))
  ) THEN RAISE EXCEPTION 'Xe không sẵn sàng hoặc không thuộc hệ thống kho'; END IF;
  IF EXISTS(SELECT 1 FROM public.chuyen_xe cx WHERE cx.xe_id=p_xe_id
    AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')) THEN
    RAISE EXCEPTION 'Xe đang có chuyến chưa hoàn thành';
  END IF;

  v_ma := 'CX' || TO_CHAR(NOW(),'YYMMDDHH24MISS') || UPPER(SUBSTR(REPLACE(gen_random_uuid()::TEXT,'-',''),1,5));
  INSERT INTO public.chuyen_xe(xe_id,ma_chuyen,trang_thai,ngay_du_kien)
  VALUES(p_xe_id,v_ma,'CHO_KHOI_HANH',p_ngay_du_kien) RETURNING id INTO v_chuyen_id;
  INSERT INTO public.chuyen_xe_chang(chuyen_xe_id,thu_tu_chuyen,kho_di_id,
    kho_den_id,nguoi_phan_cong_id,ngay_den_du_kien)
  VALUES(v_chuyen_id,1,p_kho_di_id,p_kho_den_id,v_nv_id,p_ngay_du_kien);
  RETURN v_chuyen_id;
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_xe(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(BIGINT,BIGINT,BIGINT,TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_xe(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(BIGINT,BIGINT,BIGINT,TIMESTAMPTZ) TO authenticated;
NOTIFY pgrst,'reload schema';

-- GIOI HAN QUAN LY CAP 2 CHI XE VA NHAN SU CUA KHO MINH
-- Quản lý kho cấp 2 chỉ xem/gán nhân viên và xe thuộc chính kho cấp 2.
-- Xe của kho cấp 2 vẫn được tạo chuyến lên kho cấp 1 trực thuộc.
-- Không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_xe(p_kho_id BIGINT)
RETURNS TABLE(id BIGINT,bien_so_xe VARCHAR,tai_trong NUMERIC,trang_thai VARCHAR,
  tai_xe_id BIGINT,ten_tai_xe VARCHAR,so_dien_thoai VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
    RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
  END IF;
  RETURN QUERY
  SELECT x.id,x.bien_so_xe::VARCHAR,x.tai_trong,x.trang_thai::VARCHAR,
    x.tai_xe_id,nv.ho_ten::VARCHAR,nv.so_dien_thoai::VARCHAR
  FROM public.xe x
  JOIN public.nhan_vien nv ON nv.id=x.tai_xe_id
  WHERE nv.kho_hang_id=p_kho_id
    AND nv.vai_tro='VAN_CHUYEN'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG'
    AND NOT EXISTS(
      SELECT 1 FROM public.chuyen_xe cx
      WHERE cx.xe_id=x.id
        AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')
    )
  ORDER BY CASE x.trang_thai WHEN 'SAN_SANG' THEN 0 ELSE 1 END,x.bien_so_xe;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(
  p_kho_di_id BIGINT,p_kho_den_id BIGINT,p_xe_id BIGINT,
  p_ngay_du_kien TIMESTAMPTZ DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv_id BIGINT; v_chuyen_id BIGINT; v_ma VARCHAR;
  v_cap_di SMALLINT; v_kho_cha BIGINT;
BEGIN
  IF p_kho_di_id=p_kho_den_id THEN RAISE EXCEPTION 'Kho đi và kho đến phải khác nhau'; END IF;
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_di_id) THEN
    RAISE EXCEPTION 'Bạn không quản lý kho khởi hành';
  END IF;
  SELECT nv.id INTO v_nv_id FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='QUAN_LY_KHO'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF v_nv_id IS NULL THEN RAISE EXCEPTION 'Tài khoản không phải quản lý kho'; END IF;

  SELECT kh.cap_kho,kh.kho_trung_tam_id INTO v_cap_di,v_kho_cha
  FROM public.kho_hang kh WHERE kh.id=p_kho_di_id;
  IF v_cap_di=2 AND p_kho_den_id<>v_kho_cha THEN
    RAISE EXCEPTION 'Kho cấp 2 chỉ được tạo chuyến lên kho cấp 1 trực thuộc';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.quan_ly_kho_danh_sach_kho_den(p_kho_di_id) d
    WHERE d.id=p_kho_den_id
  ) THEN RAISE EXCEPTION 'Kho đến không đúng tuyến được phép'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.xe x
    JOIN public.nhan_vien tx ON tx.id=x.tai_xe_id
    WHERE x.id=p_xe_id AND x.trang_thai='SAN_SANG'
      AND tx.vai_tro='VAN_CHUYEN'
      AND tx.kho_hang_id=p_kho_di_id
      AND tx.trang_thai_duyet='DA_DUYET'
      AND tx.trang_thai='HOAT_DONG'
  ) THEN RAISE EXCEPTION 'Xe không sẵn sàng hoặc không thuộc kho cấp 2 này'; END IF;
  IF EXISTS(SELECT 1 FROM public.chuyen_xe cx WHERE cx.xe_id=p_xe_id
    AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI')) THEN
    RAISE EXCEPTION 'Xe đang có chuyến chưa hoàn thành';
  END IF;

  v_ma := 'CX' || TO_CHAR(NOW(),'YYMMDDHH24MISS') || UPPER(SUBSTR(REPLACE(gen_random_uuid()::TEXT,'-',''),1,5));
  INSERT INTO public.chuyen_xe(xe_id,ma_chuyen,trang_thai,ngay_du_kien)
  VALUES(p_xe_id,v_ma,'CHO_KHOI_HANH',p_ngay_du_kien) RETURNING id INTO v_chuyen_id;
  INSERT INTO public.chuyen_xe_chang(chuyen_xe_id,thu_tu_chuyen,kho_di_id,
    kho_den_id,nguoi_phan_cong_id,ngay_den_du_kien)
  VALUES(v_chuyen_id,1,p_kho_di_id,p_kho_den_id,v_nv_id,p_ngay_du_kien);
  RETURN v_chuyen_id;
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_xe(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(BIGINT,BIGINT,BIGINT,TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_xe(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_gan_xe_tao_chuyen(BIGINT,BIGINT,BIGINT,TIMESTAMPTZ) TO authenticated;
NOTIFY pgrst,'reload schema';
