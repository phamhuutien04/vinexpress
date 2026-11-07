DROP FUNCTION IF EXISTS public.nhan_vien_kho_tin_nhan_telegram();
DROP FUNCTION IF EXISTS public.admin_cap_nhat_nhom_telegram_kho(BIGINT, TEXT);
DROP TABLE IF EXISTS public.tin_nhan_telegram_kho;
ALTER TABLE public.kho_hang
  DROP CONSTRAINT IF EXISTS kho_hang_telegram_group_url_check,
  DROP COLUMN IF EXISTS telegram_group_url,
  DROP COLUMN IF EXISTS telegram_chat_id;

DROP FUNCTION IF EXISTS public.admin_danh_sach_kho();
CREATE FUNCTION public.admin_danh_sach_kho()
RETURNS TABLE (
  id BIGINT, ma_kho VARCHAR, ten_kho VARCHAR, dia_chi TEXT,
  so_dien_thoai VARCHAR, trang_thai VARCHAR, cap_kho SMALLINT,
  kho_trung_tam_id BIGINT, ten_kho_trung_tam VARCHAR, khu_vuc_id BIGINT,
  tinh_thanh VARCHAR, phuong_xa VARCHAR, ngay_tao TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được xem danh sách kho'; END IF;
  RETURN QUERY SELECT kh.id, kh.ma_kho::VARCHAR, kh.ten_kho::VARCHAR, kh.dia_chi,
    kh.so_dien_thoai::VARCHAR, kh.trang_thai::VARCHAR, kh.cap_kho,
    kh.kho_trung_tam_id, trung_tam.ten_kho::VARCHAR, kh.khu_vuc_id,
    kv.tinh_thanh::VARCHAR, kv.phuong_xa::VARCHAR, kh.ngay_tao
  FROM public.kho_hang kh JOIN public.khu_vuc kv ON kv.id = kh.khu_vuc_id
  LEFT JOIN public.kho_hang trung_tam ON trung_tam.id = kh.kho_trung_tam_id
  ORDER BY kh.cap_kho, kv.tinh_thanh, kh.ten_kho;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_tong_quan()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE; v_kho public.kho_hang%ROWTYPE;
BEGIN
  SELECT * INTO v_nv FROM public.nhan_vien WHERE auth_user_id = auth.uid() AND vai_tro = 'NHAN_VIEN_KHO' AND trang_thai_duyet = 'DA_DUYET' AND trang_thai = 'HOAT_DONG';
  IF NOT FOUND OR v_nv.kho_hang_id IS NULL THEN RAISE EXCEPTION 'Nhân viên chưa được gán kho'; END IF;
  SELECT * INTO v_kho FROM public.kho_hang WHERE id = v_nv.kho_hang_id;
  RETURN jsonb_build_object(
    'nhan_vien_id', v_nv.id, 'ho_ten', v_nv.ho_ten, 'so_dien_thoai', v_nv.so_dien_thoai,
    'email', v_nv.email, 'kho_id', v_kho.id, 'ma_kho', v_kho.ma_kho,
    'ten_kho', v_kho.ten_kho, 'dia_chi', v_kho.dia_chi, 'cap_kho', v_kho.cap_kho,
    'don_tai_kho', (SELECT COUNT(*) FROM public.don_hang dh WHERE dh.kho_hien_tai_id = v_kho.id),
    'cho_xu_ly', (SELECT COUNT(*) FROM public.don_hang dh WHERE dh.kho_hien_tai_id = v_kho.id AND dh.trang_thai IN ('DEN_KHO_TRUNG_CHUYEN','DEN_KHO_DICH')),
    'da_xu_ly_hom_nay', (SELECT COUNT(*) FROM public.nhat_ky_don_hang nk WHERE nk.nhan_vien_id = v_nv.id AND nk.thoi_gian::DATE = CURRENT_DATE)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_danh_sach_kho() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nhan_vien_kho_tong_quan() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_kho() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_tong_quan() TO authenticated;
NOTIFY pgrst, 'reload schema';
