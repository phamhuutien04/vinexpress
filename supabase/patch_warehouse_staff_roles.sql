-- Hien thi day du nhan su thuoc kho, khong thay doi du lieu.
CREATE OR REPLACE FUNCTION public.quan_ly_kho_nhan_vien_theo_kho(p_kho_id BIGINT)
RETURNS TABLE (id BIGINT, ho_ten VARCHAR, so_dien_thoai VARCHAR, email VARCHAR,
    vai_tro VARCHAR, trang_thai_duyet VARCHAR, trang_thai VARCHAR,
    bien_so_xe VARCHAR, tai_trong NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
    IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
      RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
    END IF;
    RETURN QUERY
    SELECT nv.id,nv.ho_ten::VARCHAR,nv.so_dien_thoai::VARCHAR,
        nv.email::VARCHAR,nv.vai_tro::VARCHAR,nv.trang_thai_duyet::VARCHAR,
        nv.trang_thai::VARCHAR,x.bien_so_xe::VARCHAR,x.tai_trong
    FROM public.nhan_vien nv
    LEFT JOIN public.xe x ON x.tai_xe_id=nv.id
    WHERE nv.kho_hang_id=p_kho_id
      AND nv.auth_user_id IS DISTINCT FROM auth.uid()
      AND nv.vai_tro IN (
        'QUAN_LY_KHO','NHAN_VIEN_KHO','VAN_CHUYEN',
        'NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG'
      )
    ORDER BY CASE nv.vai_tro
      WHEN 'QUAN_LY_KHO' THEN 0
      WHEN 'NHAN_VIEN_KHO' THEN 1
      WHEN 'NHAN_VIEN_LAY_HANG' THEN 2
      WHEN 'NHAN_VIEN_GIAO_HANG' THEN 3
      ELSE 4 END,nv.ngay_tao DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_nhan_vien_theo_kho(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_nhan_vien_theo_kho(BIGINT) TO authenticated;
NOTIFY pgrst,'reload schema';
