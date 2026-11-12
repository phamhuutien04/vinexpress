-- Đơn giao gần (xe máy) chưa có shipper nhận sẽ tự hủy sau 5 phút.
-- Việc này chạy ở DB mỗi phút, kể cả khi khách và shipper đều đóng ứng dụng.

CREATE EXTENSION IF NOT EXISTS pg_cron;

ALTER TABLE public.don_hang
  ADD COLUMN IF NOT EXISTS thoi_gian_bat_dau_tim_shipper TIMESTAMPTZ;

ALTER TABLE public.don_hang
  ALTER COLUMN thoi_gian_bat_dau_tim_shipper SET DEFAULT NOW();

UPDATE public.don_hang
SET thoi_gian_bat_dau_tim_shipper = COALESCE(thoi_gian_bat_dau_tim_shipper, ngay_tao)
WHERE phuong_tien = 'XE_MAY'
  AND trang_thai = 'CHO_LAY_HANG'
  AND nhan_vien_hien_tai_id IS NULL
  AND thoi_gian_bat_dau_tim_shipper IS NULL;

CREATE INDEX IF NOT EXISTS idx_don_hang_tu_huy_shipper
  ON public.don_hang (thoi_gian_bat_dau_tim_shipper)
  WHERE phuong_tien = 'XE_MAY'
    AND trang_thai = 'CHO_LAY_HANG'
    AND nhan_vien_hien_tai_id IS NULL;

CREATE OR REPLACE FUNCTION public.tu_huy_don_gan_chua_co_shipper()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.don_hang AS dh
  SET trang_thai = 'DA_HUY',
      ghi_chu = CONCAT_WS(
        E'\n',
        NULLIF(BTRIM(dh.ghi_chu), ''),
        'Hệ thống tự hủy: không có shipper nhận đơn sau 5 phút.'
      ),
      ngay_cap_nhat = NOW()
  WHERE dh.phuong_tien = 'XE_MAY'
    AND dh.trang_thai = 'CHO_LAY_HANG'
    AND dh.nhan_vien_hien_tai_id IS NULL
    AND COALESCE(dh.thoi_gian_bat_dau_tim_shipper, dh.ngay_tao)
        <= NOW() - INTERVAL '5 minutes';

  -- Đóng các lời mời còn mở của những đơn đã tự hủy.
  UPDATE public.loi_moi_don_hang_shipper AS lm
  SET trang_thai = 'HET_HAN', phan_hoi_luc = NOW()
  FROM public.don_hang AS dh
  WHERE dh.id = lm.don_hang_id
    AND dh.trang_thai = 'DA_HUY'
    AND lm.trang_thai = 'DANG_MOI';
END;
$$;

DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'vinexpress-tu-huy-don-ngan-1-phut';

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  PERFORM cron.schedule(
    'vinexpress-tu-huy-don-ngan-1-phut',
    '* * * * *',
    'SELECT public.tu_huy_don_gan_chua_co_shipper();'
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
