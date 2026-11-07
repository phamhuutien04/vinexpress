-- Nạp tiền được PayOS xác nhận tự động; Admin chỉ được duyệt/từ chối yêu cầu rút tiền.
CREATE OR REPLACE FUNCTION public.admin_xu_ly_yeu_cau_vi(
  p_yeu_cau_id BIGINT, p_hanh_dong TEXT, p_ly_do TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_yeu_cau public.yeu_cau_nap_rut_vi%ROWTYPE;
  v_hanh_dong TEXT := UPPER(BTRIM(p_hanh_dong));
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được xử lý yêu cầu rút tiền'; END IF;
  IF v_hanh_dong NOT IN ('DUYET', 'TU_CHOI') THEN RAISE EXCEPTION 'Hành động xử lý không hợp lệ'; END IF;
  SELECT * INTO v_yeu_cau FROM public.yeu_cau_nap_rut_vi WHERE id = p_yeu_cau_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy yêu cầu ví #%', p_yeu_cau_id; END IF;
  IF v_yeu_cau.loai <> 'RUT_TIEN' THEN RAISE EXCEPTION 'Nạp tiền được PayOS xác nhận tự động, không cần Admin duyệt'; END IF;
  IF v_yeu_cau.trang_thai <> 'CHO_DUYET' THEN RAISE EXCEPTION 'Yêu cầu này đã được xử lý trước đó'; END IF;
  IF v_hanh_dong = 'TU_CHOI' AND NULLIF(BTRIM(COALESCE(p_ly_do, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Vui lòng nhập lý do từ chối';
  END IF;
  IF v_hanh_dong = 'DUYET' THEN
    PERFORM public.duyet_yeu_cau_rut_vi(p_yeu_cau_id);
  ELSE
    PERFORM public.tu_choi_yeu_cau_rut_vi(p_yeu_cau_id, BTRIM(p_ly_do));
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_xu_ly_yeu_cau_vi(BIGINT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_xu_ly_yeu_cau_vi(BIGINT, TEXT, TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
