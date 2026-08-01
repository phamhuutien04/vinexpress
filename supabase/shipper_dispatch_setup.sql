-- Chạy sau employee_auth_setup.sql trong Supabase SQL Editor.
-- Tự gán đơn <= 50 km cho shipper sẵn sàng, gần điểm lấy hàng nhất.

ALTER TABLE public.nhan_vien
  ADD COLUMN IF NOT EXISTS vi_do DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS kinh_do DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS san_sang_nhan_don BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.don_hang
  ADD COLUMN IF NOT EXISTS nhan_vien_hien_tai_id BIGINT
    REFERENCES public.nhan_vien(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS vi_do_lay_hang DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS kinh_do_lay_hang DOUBLE PRECISION;

CREATE OR REPLACE FUNCTION public.cap_nhat_vi_tri_shipper(
  p_vi_do DOUBLE PRECISION,
  p_kinh_do DOUBLE PRECISION,
  p_san_sang BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_vi_do NOT BETWEEN -90 AND 90 OR p_kinh_do NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Tọa độ không hợp lệ';
  END IF;

  UPDATE public.nhan_vien
  SET vi_do = p_vi_do, kinh_do = p_kinh_do, san_sang_nhan_don = p_san_sang
  WHERE auth_user_id = auth.uid()
    AND vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
    AND trang_thai = 'HOAT_DONG'
    AND trang_thai_duyet = 'DA_DUYET';

  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy shipper đang hoạt động'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.gan_shipper_gan_nhat(
  p_don_hang_id BIGINT,
  p_vi_do_lay_hang DOUBLE PRECISION,
  p_kinh_do_lay_hang DOUBLE PRECISION
)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_shipper_id BIGINT;
BEGIN
  -- Chỉ khách hàng sở hữu đơn mới được yêu cầu gán shipper.
  IF NOT EXISTS (
    SELECT 1 FROM public.don_hang dh JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    WHERE dh.id = p_don_hang_id AND kh.auth_user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'Bạn không có quyền gán shipper cho đơn này'; END IF;

  -- Không cho gán lại nếu đơn đã được nhận.
  IF EXISTS (SELECT 1 FROM public.don_hang WHERE id = p_don_hang_id AND nhan_vien_hien_tai_id IS NOT NULL) THEN
    RETURN NULL;
  END IF;

  SELECT nv.id INTO v_shipper_id
  FROM public.nhan_vien nv
  WHERE nv.vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
    AND nv.trang_thai = 'HOAT_DONG'
    AND nv.trang_thai_duyet = 'DA_DUYET'
    AND nv.san_sang_nhan_don = TRUE
    AND nv.vi_do IS NOT NULL AND nv.kinh_do IS NOT NULL
    -- Shipper chỉ có tối đa một đơn đang nhận/giao.
    AND NOT EXISTS (
      SELECT 1 FROM public.don_hang active_order
      WHERE active_order.nhan_vien_hien_tai_id = nv.id
        AND active_order.trang_thai IN ('GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG')
    )
  ORDER BY
    POWER(nv.vi_do - p_vi_do_lay_hang, 2) +
    POWER((nv.kinh_do - p_kinh_do_lay_hang) * COS(RADIANS(p_vi_do_lay_hang)), 2)
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  UPDATE public.don_hang
  SET nhan_vien_hien_tai_id = v_shipper_id,
      vi_do_lay_hang = p_vi_do_lay_hang,
      kinh_do_lay_hang = p_kinh_do_lay_hang,
      trang_thai = CASE WHEN v_shipper_id IS NULL THEN trang_thai ELSE 'GIAO_CHO_SHIPPER' END
  WHERE id = p_don_hang_id;

  RETURN v_shipper_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cap_nhat_vi_tri_shipper(DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gan_shipper_gan_nhat(BIGINT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
