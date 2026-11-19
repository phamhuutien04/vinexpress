-- VINEXPRESS - Quản trị viên xem đánh giá shipper từ khách hàng.
-- Chạy file này trong Supabase SQL Editor. Không thay đổi dữ liệu hiện có.

CREATE OR REPLACE FUNCTION public.admin_danh_sach_danh_gia()
RETURNS TABLE (
  id BIGINT,
  don_hang_id BIGINT,
  ma_van_don VARCHAR,
  diem_danh_gia INTEGER,
  binh_luan TEXT,
  ngay_tao TIMESTAMPTZ,
  khach_hang_ten VARCHAR,
  shipper_ten VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.la_admin() THEN
    RAISE EXCEPTION 'Chỉ ADMIN mới được xem đánh giá';
  END IF;

  RETURN QUERY
  SELECT
    dg.id,
    dg.don_hang_id,
    dh.ma_van_don::VARCHAR,
    dg.diem_danh_gia,
    dg.binh_luan,
    dg.ngay_tao,
    kh.ho_ten::VARCHAR,
    nv.ho_ten::VARCHAR
  FROM public.danh_gia dg
  JOIN public.don_hang dh ON dh.id = dg.don_hang_id
  JOIN public.khach_hang kh ON kh.id = dg.khach_hang_id
  JOIN public.nhan_vien nv ON nv.id = dg.nhan_vien_id
  ORDER BY dg.ngay_tao DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_danh_sach_danh_gia() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_danh_gia() TO authenticated;
NOTIFY pgrst, 'reload schema';
