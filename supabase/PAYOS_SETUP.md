# Cấu hình thanh toán PayOS cho VinExpress

Tích hợp này dùng PayOS để **nạp ví trực tuyến**. Ứng dụng Flutter không chứa
khóa bí mật: mọi yêu cầu tạo link và webhook đều đi qua Supabase Edge Function.

## 1. Cài database

Mở Supabase SQL Editor, chạy:

```sql
-- Cần có wallet_shared_setup.sql trước.
-- Sau đó chạy toàn bộ nội dung payos_wallet_setup.sql.
```

## 2. Khai báo Secrets

Trong thư mục dự án, cấu hình các giá trị lấy từ Kênh thanh toán trên PayOS:

```powershell
supabase secrets set PAYOS_CLIENT_ID="..."
supabase secrets set PAYOS_API_KEY="..."
supabase secrets set PAYOS_CHECKSUM_KEY="..."
supabase secrets set PAYOS_RETURN_URL="https://PROJECT_REF.supabase.co/functions/v1/payos-return"
supabase secrets set PAYOS_CANCEL_URL="https://PROJECT_REF.supabase.co/functions/v1/payos-return"
```

`PAYOS_RETURN_URL` và `PAYOS_CANCEL_URL` phải là URL HTTPS công khai của ứng
dụng/web. Chúng chỉ dùng để đưa khách quay lại giao diện; **webhook mới là nguồn
xác nhận thanh toán cuối cùng**.

## 3. Deploy Edge Functions

```powershell
supabase functions deploy payos-create-topup
supabase functions deploy payos-webhook --no-verify-jwt
supabase functions deploy payos-return --no-verify-jwt
```

Lấy URL webhook theo mẫu dưới đây, thay `PROJECT_REF` bằng Supabase project ref:

```text
https://PROJECT_REF.supabase.co/functions/v1/payos-webhook
```

Đăng nhập PayOS, mở Kênh thanh toán và đặt URL này làm webhook. PayOS sẽ gọi
webhook thử ngay khi xác nhận URL.

## Kiểm tra an toàn

1. Vào Ví khách hàng, chọn **Nạp tiền PayOS** và nhập tối thiểu 10.000đ.
2. Khi link PayOS được mở, thanh toán trên môi trường test trước.
3. Sau khi PayOS gửi webhook hợp lệ, số dư tăng đúng một lần và lịch sử có giao
   dịch `NAP_TIEN`.

Webhook kiểm tra HMAC SHA-256 bằng `PAYOS_CHECKSUM_KEY`, đối chiếu số tiền và
khóa giao dịch. Vì vậy mở URL return/cancel hoặc gọi app trực tiếp không thể tự
cộng tiền vào ví.
