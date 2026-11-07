-- PayOS dùng trực tiếp yêu cầu nạp/rút ví: giữ lịch sử, bỏ bảng phụ giao_dich_payos.
ALTER TABLE public.yeu_cau_nap_rut_vi
  ADD COLUMN IF NOT EXISTS ma_don_payos BIGINT,
  ADD COLUMN IF NOT EXISTS ma_tham_chieu TEXT;

-- Chuyển lịch sử giao dịch cũ sang yêu cầu ví trước khi bỏ bảng cũ.
UPDATE public.yeu_cau_nap_rut_vi yc
SET ma_don_payos = gp.ma_don_payos,
    ma_tham_chieu = gp.ma_tham_chieu
FROM public.giao_dich_payos gp
WHERE gp.yeu_cau_nap_rut_id = yc.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_yeu_cau_nap_rut_ma_don_payos
  ON public.yeu_cau_nap_rut_vi(ma_don_payos)
  WHERE ma_don_payos IS NOT NULL;

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

  RETURN QUERY UPDATE public.yeu_cau_nap_rut_vi AS yc
  SET ma_don_payos = COALESCE(ma_don_payos, nextval('public.payos_ma_don_hang_seq'))
  WHERE yc.id = v_yeu_cau.id
  RETURNING yc.id, yc.ma_don_payos, yc.so_tien;
END;
$$;

CREATE OR REPLACE FUNCTION public.xac_nhan_giao_dich_payos_nap_vi(
  p_ma_don_payos BIGINT, p_payment_link_id TEXT, p_ma_tham_chieu TEXT,
  p_so_tien NUMERIC, p_du_lieu_webhook JSONB DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_yeu_cau public.yeu_cau_nap_rut_vi%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' THEN RAISE EXCEPTION 'Chỉ hệ thống PayOS được xác nhận thanh toán'; END IF;
  SELECT * INTO v_yeu_cau FROM public.yeu_cau_nap_rut_vi
  WHERE ma_don_payos = p_ma_don_payos FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy yêu cầu nạp PayOS'; END IF;
  IF v_yeu_cau.trang_thai = 'DA_DUYET' THEN RETURN; END IF;
  IF v_yeu_cau.loai <> 'NAP_TIEN' OR v_yeu_cau.phuong_thuc <> 'PAYOS'
     OR v_yeu_cau.trang_thai <> 'CHO_DUYET' THEN
    RAISE EXCEPTION 'Yêu cầu nạp ví không còn chờ thanh toán';
  END IF;
  IF ROUND(COALESCE(p_so_tien, 0), 0) <> ROUND(v_yeu_cau.so_tien, 0) THEN
    RAISE EXCEPTION 'Số tiền PayOS không khớp';
  END IF;

  UPDATE public.vi SET so_du = so_du + v_yeu_cau.so_tien, ngay_cap_nhat = NOW()
  WHERE id = v_yeu_cau.vi_id;
  UPDATE public.yeu_cau_nap_rut_vi
  SET trang_thai = 'DA_DUYET', ma_tham_chieu = NULLIF(BTRIM(p_ma_tham_chieu), ''), ngay_xu_ly = NOW()
  WHERE id = v_yeu_cau.id;
  INSERT INTO public.giao_dich_vi(vi_id, yeu_cau_nap_rut_id, loai, so_tien, so_du_sau, noi_dung)
  SELECT v.id, v_yeu_cau.id, 'NAP_TIEN', v_yeu_cau.so_tien, v.so_du, 'Nạp tiền PayOS đã xác nhận'
  FROM public.vi v WHERE v.id = v_yeu_cau.vi_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trang_thai_giao_dich_payos(p_ma_don_payos BIGINT)
RETURNS TABLE (trang_thai VARCHAR, so_tien NUMERIC)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT CASE WHEN yc.trang_thai = 'DA_DUYET' THEN 'DA_THANH_TOAN' ELSE 'CHO_THANH_TOAN' END,
         yc.so_tien
  FROM public.yeu_cau_nap_rut_vi yc
  JOIN public.vi v ON v.id = yc.vi_id
  LEFT JOIN public.khach_hang kh ON kh.id = v.khach_hang_id
  LEFT JOIN public.nhan_vien nv ON nv.id = v.nhan_vien_id
  WHERE yc.ma_don_payos = p_ma_don_payos
    AND yc.loai = 'NAP_TIEN' AND yc.phuong_thuc = 'PAYOS'
    AND (kh.auth_user_id = auth.uid() OR nv.auth_user_id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.huy_giao_dich_payos_nap_vi(p_ma_don_payos BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_yeu_cau public.yeu_cau_nap_rut_vi%ROWTYPE;
BEGIN
  SELECT yc.* INTO v_yeu_cau
  FROM public.yeu_cau_nap_rut_vi yc
  JOIN public.vi v ON v.id = yc.vi_id
  LEFT JOIN public.khach_hang kh ON kh.id = v.khach_hang_id
  LEFT JOIN public.nhan_vien nv ON nv.id = v.nhan_vien_id
  WHERE yc.ma_don_payos = p_ma_don_payos
    AND (kh.auth_user_id = auth.uid() OR nv.auth_user_id = auth.uid())
  FOR UPDATE OF yc;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy giao dịch PayOS của bạn'; END IF;
  IF v_yeu_cau.trang_thai = 'DA_DUYET' THEN RAISE EXCEPTION 'Giao dịch đã thanh toán, không thể hủy'; END IF;
  IF v_yeu_cau.trang_thai <> 'CHO_DUYET' THEN RETURN; END IF;
  UPDATE public.yeu_cau_nap_rut_vi
  SET trang_thai = 'TU_CHOI', ly_do_tu_choi = 'Khách hàng hủy thanh toán PayOS', ngay_xu_ly = NOW()
  WHERE id = v_yeu_cau.id;
END;
$$;

DROP TABLE public.giao_dich_payos;
NOTIFY pgrst, 'reload schema';
