-- VINEXPRESS - Mỗi shipper chỉ được giữ một đơn chưa hoàn thành.
-- Chạy toàn bộ file trong Supabase SQL Editor.

-- Dọn dữ liệu cũ an toàn: nếu shipper đang có một đơn đã lấy hàng/đang giao,
-- trả các đơn CHO_LAY_HANG khác về hàng chờ để shipper khác nhận.
UPDATE public.don_hang cho_lay
SET nhan_vien_hien_tai_id = NULL
WHERE cho_lay.trang_thai = 'CHO_LAY_HANG'
  AND cho_lay.nhan_vien_hien_tai_id IS NOT NULL
  AND EXISTS (
      SELECT 1
      FROM public.don_hang dang_giao
      WHERE dang_giao.nhan_vien_hien_tai_id = cho_lay.nhan_vien_hien_tai_id
        AND dang_giao.id <> cho_lay.id
        AND dang_giao.trang_thai IN (
            'DA_LAY_HANG', 'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG'
        )
  );

-- Nếu dữ liệu cũ có nhiều đơn đều chưa lấy, chỉ giữ đơn tạo sớm nhất.
WITH xep_hang AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY nhan_vien_hien_tai_id
            ORDER BY ngay_tao, id
        ) AS thu_tu
    FROM public.don_hang
    WHERE nhan_vien_hien_tai_id IS NOT NULL
      AND trang_thai = 'CHO_LAY_HANG'
)
UPDATE public.don_hang dh
SET nhan_vien_hien_tai_id = NULL
FROM xep_hang xh
WHERE dh.id = xh.id
  AND xh.thu_tu > 1;

-- Hàm nhận đơn và hàm tìm đơn nằm trong file này.
-- Chạy tiếp toàn bộ shipper_nearby_orders_setup.sql sau file hiện tại.
