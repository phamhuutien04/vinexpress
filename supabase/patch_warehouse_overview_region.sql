-- Bổ sung tỉnh/thành và phường/xã của kho vào dữ liệu tổng quan.
-- Không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_tong_quan_theo_kho(p_kho_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_kho public.kho_hang%ROWTYPE; v_quan_ly_ten TEXT;
  v_tinh_thanh VARCHAR; v_phuong_xa VARCHAR;
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
    RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
  END IF;
  SELECT * INTO v_kho FROM public.kho_hang WHERE id=p_kho_id;
  SELECT nv.ho_ten INTO v_quan_ly_ten FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid();
  SELECT kv.tinh_thanh,kv.phuong_xa INTO v_tinh_thanh,v_phuong_xa
  FROM public.khu_vuc kv WHERE kv.id=v_kho.khu_vuc_id;

  RETURN jsonb_build_object(
    'quan_ly_ten',v_quan_ly_ten,'kho_id',v_kho.id,
    'ma_kho',v_kho.ma_kho,'ten_kho',v_kho.ten_kho,
    'dia_chi',v_kho.dia_chi,'cap_kho',v_kho.cap_kho,
    'tinh_thanh',v_tinh_thanh,'phuong_xa',v_phuong_xa,
    'don_tai_kho',(SELECT COUNT(*) FROM public.don_hang dh WHERE dh.kho_hien_tai_id=v_kho.id),
    'don_cho_xu_ly',(SELECT COUNT(*) FROM public.don_hang dh WHERE
      (dh.kho_gui_id=v_kho.id OR dh.kho_dich_id=v_kho.id OR dh.kho_hien_tai_id=v_kho.id)
      AND dh.trang_thai IN ('DA_LAY_HANG','DEN_KHO_TRUNG_CHUYEN','DEN_KHO_DICH')),
    'dang_van_chuyen',(SELECT COUNT(*) FROM public.don_hang dh WHERE
      (dh.kho_gui_id=v_kho.id OR dh.kho_dich_id=v_kho.id) AND dh.trang_thai='DANG_VAN_CHUYEN'),
    'da_giao',(SELECT COUNT(*) FROM public.don_hang dh WHERE
      (dh.kho_gui_id=v_kho.id OR dh.kho_dich_id=v_kho.id) AND dh.trang_thai='DA_GIAO_HANG')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.quan_ly_kho_tong_quan_theo_kho(BIGINT) TO authenticated;
NOTIFY pgrst,'reload schema';
