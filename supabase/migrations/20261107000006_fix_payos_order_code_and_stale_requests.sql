-- Tránh trùng tên giữa cột ma_don_payos và biến OUT của hàm trả về.
CREATE OR REPLACE FUNCTION public.tao_giao_dich_payos_nap_vi(
  p_yeu_cau_nap_rut_id BIGINT
)
RETURNS TABLE (id BIGINT, ma_don_payos BIGINT, so_tien NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_yeu_cau public.yeu_cau_nap_rut_vi%ROWTYPE;
BEGIN
  SELECT yc.* INTO v_yeu_cau
  FROM public.yeu_cau_nap_rut_vi yc
  JOIN public.vi v ON v.id = yc.vi_id
  LEFT JOIN public.khach_hang kh ON kh.id = v.khach_hang_id
  LEFT JOIN public.nhan_vien nv ON nv.id = v.nhan_vien_id
  WHERE yc.id = p_yeu_cau_nap_rut_id
    AND (kh.auth_user_id = auth.uid() OR nv.auth_user_id = auth.uid())
  FOR UPDATE OF yc;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy yêu cầu nạp ví của bạn'; END IF;
  IF v_yeu_cau.loai <> 'NAP_TIEN' OR v_yeu_cau.phuong_thuc <> 'PAYOS'
     OR v_yeu_cau.trang_thai <> 'CHO_DUYET' THEN
    RAISE EXCEPTION 'Yêu cầu nạp ví không còn hợp lệ để thanh toán PayOS';
  END IF;

  RETURN QUERY
  UPDATE public.yeu_cau_nap_rut_vi AS yc
  SET ma_don_payos = COALESCE(yc.ma_don_payos, nextval('public.payos_ma_don_hang_seq'))
  WHERE yc.id = v_yeu_cau.id
  RETURNING yc.id, yc.ma_don_payos, yc.so_tien;
END;
$$;

NOTIFY pgrst, 'reload schema';
