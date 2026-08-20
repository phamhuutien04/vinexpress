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
