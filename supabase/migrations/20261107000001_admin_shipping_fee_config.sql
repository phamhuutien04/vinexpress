CREATE OR REPLACE FUNCTION public.admin_cau_hinh_phi_van_chuyen()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được xem cấu hình phí vận chuyển'; END IF;
  RETURN (SELECT jsonb_build_object(
    'phi_xe_may_moi_km', COALESCE(phi_van_chuyen, 5000),
    'phi_xe_tai', COALESCE(phi_xe_tai, 30000),
    'phi_moi_kg', COALESCE(phi_moi_kg, 3000),
    'phan_tram_san', COALESCE(phan_tram_san, 20)
  ) FROM public.phi_van_chuyen WHERE id = 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_cap_nhat_cau_hinh_phi_van_chuyen(
  p_phi_xe_may_moi_km NUMERIC, p_phi_xe_tai NUMERIC,
  p_phi_moi_kg NUMERIC, p_phan_tram_san NUMERIC
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được cập nhật cấu hình phí vận chuyển'; END IF;
  IF p_phi_xe_may_moi_km < 0 OR p_phi_xe_tai < 0 OR p_phi_moi_kg < 0 OR p_phan_tram_san < 0 OR p_phan_tram_san > 100 THEN
    RAISE EXCEPTION 'Mức phí phải từ 0 trở lên và phần trăm sàn từ 0 đến 100';
  END IF;
  UPDATE public.phi_van_chuyen SET
    phi_van_chuyen = ROUND(p_phi_xe_may_moi_km, 2), phi_xe_tai = ROUND(p_phi_xe_tai, 2),
    phi_moi_kg = ROUND(p_phi_moi_kg, 2), phan_tram_san = ROUND(p_phan_tram_san, 2), ngay_cap_nhat = NOW()
  WHERE id = 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chưa có cấu hình phí vận chuyển'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cau_hinh_phi_van_chuyen() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_cap_nhat_cau_hinh_phi_van_chuyen(NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cau_hinh_phi_van_chuyen() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cap_nhat_cau_hinh_phi_van_chuyen(NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;
NOTIFY pgrst, 'reload schema';
