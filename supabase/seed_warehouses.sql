-- ============================================================
-- DỮ LIỆU MẪU KHU VỰC VÀ KHO HÀNG
-- Dùng mô hình hành chính mới từ 01/07/2025:
-- tỉnh/thành phố -> phường/xã/đặc khu (không dùng quận/huyện).
-- Chạy trong Supabase Dashboard > SQL Editor.
-- ============================================================

BEGIN;

-- `quan_huyen` chỉ được giữ tạm để tương thích schema cũ; không còn là
-- thành phần định danh hay dùng để tra kho.
ALTER TABLE public.khu_vuc
    ALTER COLUMN quan_huyen DROP NOT NULL;

-- Đồng bộ cách ghi tên tỉnh/thành đúng với API hành chính v2 mà ứng dụng dùng.
UPDATE public.khu_vuc
SET tinh_thanh = CASE tinh_thanh
    WHEN 'TP. Hồ Chí Minh' THEN 'Thành phố Hồ Chí Minh'
    WHEN 'Hà Nội' THEN 'Thành phố Hà Nội'
    WHEN 'Đà Nẵng' THEN 'Thành phố Đà Nẵng'
    WHEN 'Cần Thơ' THEN 'Thành phố Cần Thơ'
    ELSE tinh_thanh
END
WHERE tinh_thanh IN ('TP. Hồ Chí Minh', 'Hà Nội', 'Đà Nẵng', 'Cần Thơ');

-- Chuẩn hoá các bản ghi mẫu đã có theo cấp hành chính mới.
UPDATE public.khu_vuc
SET quan_huyen = NULL
WHERE (ten_khu_vuc, tinh_thanh, phuong_xa) IN (
    ('Trung tâm TP.HCM', 'Thành phố Hồ Chí Minh', 'Phường Sài Gòn'),
    ('Phía Đông TP.HCM', 'Thành phố Hồ Chí Minh', 'Phường An Phú'),
    ('Trung tâm Hà Nội', 'Thành phố Hà Nội', 'Phường Hoàn Kiếm'),
    ('Phía Tây Hà Nội', 'Thành phố Hà Nội', 'Phường Từ Liêm'),
    ('Trung tâm Đà Nẵng', 'Thành phố Đà Nẵng', 'Phường Hải Châu'),
    ('Trung tâm Cần Thơ', 'Thành phố Cần Thơ', 'Phường Ninh Kiều')
);

-- Thêm khu vực nào chưa tồn tại, định danh bằng tỉnh/thành và phường/xã.
INSERT INTO public.khu_vuc (ten_khu_vuc, tinh_thanh, phuong_xa)
SELECT v.ten_khu_vuc, v.tinh_thanh, v.phuong_xa
FROM (
    VALUES
        ('Trung tâm TP.HCM', 'Thành phố Hồ Chí Minh', 'Phường Sài Gòn'),
        ('Phía Đông TP.HCM', 'Thành phố Hồ Chí Minh', 'Phường An Phú'),
        ('Trung tâm Hà Nội', 'Thành phố Hà Nội', 'Phường Hoàn Kiếm'),
        ('Phía Tây Hà Nội', 'Thành phố Hà Nội', 'Phường Từ Liêm'),
        ('Trung tâm Đà Nẵng', 'Thành phố Đà Nẵng', 'Phường Hải Châu'),
        ('Trung tâm Cần Thơ', 'Thành phố Cần Thơ', 'Phường Ninh Kiều')
) AS v(ten_khu_vuc, tinh_thanh, phuong_xa)
WHERE NOT EXISTS (
    SELECT 1
    FROM public.khu_vuc AS kv
    WHERE kv.ten_khu_vuc = v.ten_khu_vuc
      AND kv.tinh_thanh = v.tinh_thanh
      AND kv.phuong_xa = v.phuong_xa
);

-- Thêm kho mẫu và liên kết bằng tỉnh/thành + phường/xã mới.
INSERT INTO public.kho_hang (
    ma_kho, ten_kho, dia_chi, khu_vuc_id, so_dien_thoai, trang_thai
)
SELECT
    v.ma_kho,
    v.ten_kho,
    v.dia_chi,
    kv.id,
    v.so_dien_thoai,
    'HOAT_DONG'
FROM (
    VALUES
        ('HCM-Q1', 'Kho trung tâm Sài Gòn',
            '12 Nguyễn Huệ, Phường Sài Gòn, Thành phố Hồ Chí Minh',
            'Thành phố Hồ Chí Minh', 'Phường Sài Gòn', '02838220001'),
        ('HCM-AP', 'Kho trung chuyển An Phú',
            '86 Mai Chí Thọ, Phường An Phú, Thành phố Hồ Chí Minh',
            'Thành phố Hồ Chí Minh', 'Phường An Phú', '02837240002'),
        ('HN-HK', 'Kho trung tâm Hoàn Kiếm',
            '25 Tràng Tiền, Phường Hoàn Kiếm, Thành phố Hà Nội',
            'Thành phố Hà Nội', 'Phường Hoàn Kiếm', '02439260003'),
        ('HN-TL', 'Kho trung chuyển Từ Liêm',
            '18 Hàm Nghi, Phường Từ Liêm, Thành phố Hà Nội',
            'Thành phố Hà Nội', 'Phường Từ Liêm', '02437680004'),
        ('DNG-HC', 'Kho trung tâm Hải Châu',
            '40 Bạch Đằng, Phường Hải Châu, Thành phố Đà Nẵng',
            'Thành phố Đà Nẵng', 'Phường Hải Châu', '02363560005'),
        ('CT-NK', 'Kho trung tâm Ninh Kiều',
            '15 Hai Bà Trưng, Phường Ninh Kiều, Thành phố Cần Thơ',
            'Thành phố Cần Thơ', 'Phường Ninh Kiều', '02923760006')
) AS v(ma_kho, ten_kho, dia_chi, tinh_thanh, phuong_xa, so_dien_thoai)
JOIN public.khu_vuc AS kv
  ON kv.tinh_thanh = v.tinh_thanh
 AND kv.phuong_xa = v.phuong_xa
ON CONFLICT (ma_kho) DO UPDATE SET
    ten_kho = EXCLUDED.ten_kho,
    dia_chi = EXCLUDED.dia_chi,
    khu_vuc_id = EXCLUDED.khu_vuc_id,
    so_dien_thoai = EXCLUDED.so_dien_thoai,
    trang_thai = EXCLUDED.trang_thai;

COMMIT;

-- Kiểm tra kết quả: không còn dùng `quan_huyen` để vận hành.
SELECT
    kh.id,
    kh.ma_kho,
    kh.ten_kho,
    kh.dia_chi,
    kh.so_dien_thoai,
    kh.trang_thai,
    kv.ten_khu_vuc,
    kv.tinh_thanh,
    kv.phuong_xa
FROM public.kho_hang AS kh
JOIN public.khu_vuc AS kv ON kv.id = kh.khu_vuc_id
ORDER BY kh.ma_kho;
