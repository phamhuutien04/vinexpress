-- VINEXPRESS - Cài riêng chức năng khách hàng theo dõi đơn hàng.
-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor.
-- Yêu cầu các bảng don_hang, khach_hang, nhan_vien và vi_tri_nhan_vien đã tồn tại.

DROP FUNCTION IF EXISTS public.theo_doi_don_hang_khach_hang(BIGINT);

CREATE OR REPLACE FUNCTION public.theo_doi_don_hang_khach_hang(
    p_don_hang_id BIGINT
)
RETURNS TABLE (
    don_hang_id BIGINT,
    ma_van_don VARCHAR,
    trang_thai VARCHAR,
    nguoi_gui_dia_chi TEXT,
    nguoi_nhan_dia_chi TEXT,
    shipper_ten VARCHAR,
    shipper_sdt VARCHAR,
    shipper_vi_do DOUBLE PRECISION,
    shipper_kinh_do DOUBLE PRECISION,
    vi_tri_cap_nhat_luc TIMESTAMPTZ,
    diem_den_vi_do DOUBLE PRECISION,
    diem_den_kinh_do DOUBLE PRECISION,
    diem_den_dia_chi TEXT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT
        dh.id,
        dh.ma_van_don,
        dh.trang_thai,
        dh.nguoi_gui_dia_chi,
        dh.nguoi_nhan_dia_chi,
        nv.ho_ten,
        nv.so_dien_thoai,
        vt.vi_do,
        vt.kinh_do,
        vt.thoi_gian_cap_nhat,
        CASE
            WHEN dh.trang_thai IN (
                'DA_LAY_HANG', 'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG'
            ) THEN dh.nguoi_nhan_vi_do
            ELSE dh.nguoi_gui_vi_do
        END,
        CASE
            WHEN dh.trang_thai IN (
                'DA_LAY_HANG', 'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG'
            ) THEN dh.nguoi_nhan_kinh_do
            ELSE dh.nguoi_gui_kinh_do
        END,
        CASE
            WHEN dh.trang_thai IN (
                'DA_LAY_HANG', 'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG'
            ) THEN dh.nguoi_nhan_dia_chi
            ELSE dh.nguoi_gui_dia_chi
        END
    FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    LEFT JOIN public.nhan_vien nv ON nv.id = dh.nhan_vien_hien_tai_id
    LEFT JOIN public.vi_tri_nhan_vien vt ON vt.nhan_vien_id = nv.id
    WHERE dh.id = p_don_hang_id
      AND kh.auth_user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.theo_doi_don_hang_khach_hang(BIGINT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.theo_doi_don_hang_khach_hang(BIGINT)
TO authenticated;

-- Buộc PostgREST nhận hàm mới ngay, tránh lỗi 404/PGRST202 do schema cache.
NOTIFY pgrst, 'reload schema';

-- Kiểm tra sau khi chạy (phải trả về đúng 1 dòng):
SELECT
    p.proname AS ten_ham,
    pg_get_function_identity_arguments(p.oid) AS tham_so
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'theo_doi_don_hang_khach_hang';
