-- Kiểm tra vì sao ô "Kho đến" của kho cấp 2 bị trống.
-- Script không xóa dữ liệu.

SELECT
  con.id,
  con.ma_kho,
  con.ten_kho,
  con.cap_kho,
  con.kho_trung_tam_id,
  cha.ma_kho AS ma_kho_cap_1,
  cha.ten_kho AS ten_kho_cap_1,
  cha.trang_thai AS trang_thai_kho_cap_1
FROM public.kho_hang con
LEFT JOIN public.kho_hang cha ON cha.id=con.kho_trung_tam_id
WHERE con.cap_kho=2
ORDER BY con.ten_kho;

-- Sửa riêng dữ liệu mẫu Kho An Phú nếu bản ghi cũ chưa liên kết đúng.
-- Chỉ chạy UPDATE khi cả HCM-AP và HCM-Q1 cùng tồn tại.
UPDATE public.kho_hang AS con
SET kho_trung_tam_id=cha.id,ngay_cap_nhat=NOW()
FROM public.kho_hang AS cha
WHERE con.ma_kho='HCM-AP'
  AND cha.ma_kho='HCM-Q1'
  AND con.cap_kho=2
  AND con.kho_trung_tam_id IS DISTINCT FROM cha.id;

UPDATE public.kho_hang
SET trang_thai='HOAT_DONG',ngay_cap_nhat=NOW()
WHERE ma_kho='HCM-Q1' AND trang_thai<>'HOAT_DONG';

NOTIFY pgrst,'reload schema';
