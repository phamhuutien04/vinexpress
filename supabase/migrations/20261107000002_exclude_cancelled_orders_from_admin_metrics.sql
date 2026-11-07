-- Đơn đã hủy chỉ dùng để tra cứu, không đưa vào số liệu vận hành hoặc doanh thu.
CREATE OR REPLACE FUNCTION public.admin_tong_quan()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_ket_qua JSONB;
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được truy cập chức năng này'; END IF;
  SELECT jsonb_build_object(
    'tong_nhan_vien', (SELECT COUNT(*) FROM public.nhan_vien WHERE auth_user_id IS DISTINCT FROM auth.uid()),
    'nhan_vien_cho_duyet', (SELECT COUNT(*) FROM public.nhan_vien WHERE trang_thai_duyet = 'CHO_DUYET' AND auth_user_id IS DISTINCT FROM auth.uid()),
    'tong_khach_hang', (SELECT COUNT(*) FROM public.khach_hang),
    'tong_don_hang', (SELECT COUNT(*) FROM public.don_hang WHERE trang_thai <> 'DA_HUY'),
    'don_cho_lay', (SELECT COUNT(*) FROM public.don_hang WHERE trang_thai = 'CHO_LAY_HANG'),
    'don_dang_giao', (SELECT COUNT(*) FROM public.don_hang WHERE trang_thai IN ('DA_LAY_HANG', 'DANG_VAN_CHUYEN', 'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG')),
    'don_da_giao', (SELECT COUNT(*) FROM public.don_hang WHERE trang_thai = 'DA_GIAO_HANG'),
    'tong_doanh_thu_van_chuyen', (SELECT COALESCE(SUM(phi_van_chuyen), 0) FROM public.don_hang WHERE trang_thai = 'DA_GIAO_HANG')
  ) INTO v_ket_qua;
  RETURN v_ket_qua;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_tong_quan() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tong_quan() TO authenticated;
NOTIFY pgrst, 'reload schema';
