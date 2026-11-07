-- Cấu hình tỷ lệ nền tảng khấu trừ từ phí giao hàng của shipper.
-- Tỷ lệ chỉ được sử dụng khi ghi nhận thu nhập cho các đơn hoàn thành sau đó.
CREATE OR REPLACE FUNCTION public.admin_cau_hinh_chiet_khau_shipper()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được xem cấu hình chiết khấu shipper'; END IF;
  RETURN (
    SELECT jsonb_build_object('phan_tram_san', COALESCE(phan_tram_san, 20))
    FROM public.phi_van_chuyen WHERE id = 1
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_cap_nhat_chiet_khau_shipper(
  p_phan_tram_san NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được cập nhật chiết khấu shipper'; END IF;
  IF p_phan_tram_san IS NULL OR p_phan_tram_san < 0 OR p_phan_tram_san > 100 THEN
    RAISE EXCEPTION 'Chiết khấu phải nằm trong khoảng 0 đến 100 phần trăm';
  END IF;
  UPDATE public.phi_van_chuyen
  SET phan_tram_san = ROUND(p_phan_tram_san, 2), ngay_cap_nhat = NOW()
  WHERE id = 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chưa có cấu hình phí vận chuyển'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_cau_hinh_chiet_khau_shipper() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_cap_nhat_chiet_khau_shipper(NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cau_hinh_chiet_khau_shipper() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cap_nhat_chiet_khau_shipper(NUMERIC) TO authenticated;
NOTIFY pgrst, 'reload schema';
