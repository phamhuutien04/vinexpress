-- Nhật ký đơn hàng dành cho quản trị viên.
-- Gom cả sự kiện tạo đơn, quét hàng, thay đổi trạng thái, kho thao tác
-- và ảnh minh chứng để xem theo một dòng thời gian duy nhất.

CREATE OR REPLACE FUNCTION public.admin_chi_tiet_lich_su_don_hang(
  p_don_hang_id BIGINT
)
RETURNS TABLE (
  nhat_ky_id BIGINT,
  hanh_dong TEXT,
  trang_thai_cu VARCHAR,
  trang_thai_moi VARCHAR,
  ghi_chu TEXT,
  minh_chung TEXT,
  thoi_gian TIMESTAMPTZ,
  ten_nhan_vien VARCHAR,
  vai_tro VARCHAR,
  ten_kho VARCHAR,
  ma_kho VARCHAR,
  ma_chuyen VARCHAR,
  bien_so_xe VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.la_admin() THEN
    RAISE EXCEPTION 'Chỉ ADMIN mới được xem nhật ký chi tiết đơn hàng';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.don_hang WHERE id = p_don_hang_id) THEN
    RAISE EXCEPTION 'Không tìm thấy đơn hàng';
  END IF;

  RETURN QUERY
  WITH chuyen_gan_nhat AS (
    SELECT cx.ma_chuyen::VARCHAR AS ma_chuyen, x.bien_so_xe::VARCHAR AS bien_so_xe
    FROM public.chi_tiet_chuyen_xe ct
    JOIN public.chuyen_xe cx ON cx.id = ct.chuyen_xe_id
    LEFT JOIN public.xe x ON x.id = cx.xe_id
    WHERE ct.don_hang_id = p_don_hang_id
    ORDER BY COALESCE(ct.ngay_do_hang, ct.ngay_xep_hang) DESC, ct.id DESC
    LIMIT 1
  ), su_kien AS (
    SELECT
      0::BIGINT AS nhat_ky_id,
      'Tạo đơn hàng'::TEXT AS hanh_dong,
      NULL::VARCHAR AS trang_thai_cu,
      dh.trang_thai::VARCHAR AS trang_thai_moi,
      'Khách hàng tạo đơn vận chuyển'::TEXT AS ghi_chu,
      NULL::TEXT AS minh_chung,
      dh.ngay_tao AS thoi_gian,
      kh.ho_ten::VARCHAR AS ten_nhan_vien,
      'KHACH_HANG'::VARCHAR AS vai_tro,
      NULL::VARCHAR AS ten_kho,
      NULL::VARCHAR AS ma_kho
    FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    WHERE dh.id = p_don_hang_id

    UNION ALL

    SELECT
      nk.id,
      nk.hanh_dong::TEXT,
      nk.trang_thai_cu::VARCHAR,
      nk.trang_thai_moi::VARCHAR,
      nk.ghi_chu,
      nk.minh_chung,
      nk.thoi_gian,
      nv.ho_ten::VARCHAR,
      nv.vai_tro::VARCHAR,
      kho.ten_kho::VARCHAR,
      kho.ma_kho::VARCHAR
    FROM public.nhat_ky_don_hang nk
    LEFT JOIN public.nhan_vien nv ON nv.id = nk.nhan_vien_id
    LEFT JOIN public.kho_hang kho ON kho.id = nk.kho_id
    WHERE nk.don_hang_id = p_don_hang_id
  )
  SELECT
    su_kien.nhat_ky_id,
    su_kien.hanh_dong,
    su_kien.trang_thai_cu,
    su_kien.trang_thai_moi,
    su_kien.ghi_chu,
    su_kien.minh_chung,
    su_kien.thoi_gian,
    su_kien.ten_nhan_vien,
    su_kien.vai_tro,
    su_kien.ten_kho,
    su_kien.ma_kho,
    chuyen_gan_nhat.ma_chuyen,
    chuyen_gan_nhat.bien_so_xe
  FROM su_kien
  LEFT JOIN chuyen_gan_nhat ON TRUE
  ORDER BY su_kien.thoi_gian ASC, su_kien.nhat_ky_id ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_chi_tiet_lich_su_don_hang(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_chi_tiet_lich_su_don_hang(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';
