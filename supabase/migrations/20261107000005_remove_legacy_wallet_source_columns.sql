-- Hai cột này chỉ phục vụ chuyển dữ liệu từ các bảng ví cũ, không còn dùng
-- trong luồng nạp PayOS hoặc rút tiền hiện tại.
DROP INDEX IF EXISTS public.uq_yeu_cau_nap_rut_nguon;

ALTER TABLE public.yeu_cau_nap_rut_vi
  DROP COLUMN IF EXISTS nguon_bang,
  DROP COLUMN IF EXISTS nguon_id;

NOTIFY pgrst, 'reload schema';
