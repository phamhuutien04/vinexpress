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
