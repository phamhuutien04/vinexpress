# Cài đặt trang Admin VinExpress

1. Chạy `warehouse_hierarchy_setup.sql`, sau đó chạy `admin_setup.sql`
   trong Supabase SQL Editor. Mục Kho hàng hỗ trợ kho trung tâm cấp 1 và
   kho vệ tinh cấp 2 trực thuộc kho cấp 1 cùng tỉnh/thành.
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

Mỗi khi sửa chức năng tạo nhân viên (ví dụ thêm tài xế xe tải, biển số và
tải trọng), phải chạy lại lệnh deploy trên. Chỉ lưu file trong dự án sẽ không
tự cập nhật Edge Function đang chạy trên Supabase.

`SUPABASE_URL`, `SUPABASE_ANON_KEY` và `SUPABASE_SERVICE_ROLE_KEY` được Supabase
tự cung cấp trong môi trường Edge Function. Không đưa service-role key vào Flutter.

4. Đăng xuất rồi đăng nhập lại bằng tài khoản Admin.
