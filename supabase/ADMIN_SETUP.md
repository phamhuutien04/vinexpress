# Cài đặt trang Admin VinExpress

1. Chạy `admin_setup.sql` trong Supabase SQL Editor.
2. Nâng một tài khoản nhân viên hiện có thành Admin:

```sql
UPDATE public.nhan_vien
SET vai_tro = 'ADMIN',
    trang_thai_duyet = 'DA_DUYET',
    trang_thai = 'HOAT_DONG'
WHERE email = 'EMAIL_ADMIN_CUA_BAN';
```

3. Triển khai Edge Function tạo tài khoản nhân viên (thay project ref nếu cần):

```bash
supabase functions deploy admin-create-employee \
  --project-ref klhzughpwbnyffxwcjyx
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` và `SUPABASE_SERVICE_ROLE_KEY` được Supabase
tự cung cấp trong môi trường Edge Function. Không đưa service-role key vào Flutter.

4. Đăng xuất rồi đăng nhập lại bằng tài khoản Admin.
