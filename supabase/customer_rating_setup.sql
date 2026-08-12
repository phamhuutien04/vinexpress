-- VINEXPRESS - Cài chức năng khách hàng đánh giá shipper sau khi giao hàng.
-- Chạy toàn bộ file trong Supabase SQL Editor. Không xóa dữ liệu hiện tại.

DROP FUNCTION IF EXISTS public.don_hang_cua_khach_hang();

CREATE OR REPLACE FUNCTION public.don_hang_cua_khach_hang()
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    trang_thai VARCHAR,
    nguoi_gui_ten VARCHAR,
    nguoi_gui_dia_chi TEXT,
    nguoi_gui_sdt VARCHAR,
    nguoi_nhan_ten VARCHAR,
    nguoi_nhan_dia_chi TEXT,
    nguoi_nhan_sdt VARCHAR,
    can_nang NUMERIC,
    gia_tri_hang NUMERIC,
    phi_van_chuyen NUMERIC,
    cod NUMERIC,
    khoang_cach_km NUMERIC,
    phuong_tien VARCHAR,
    ghi_chu TEXT,
    ngay_tao TIMESTAMPTZ,
    ngay_lay_hang TIMESTAMPTZ,
    ngay_giao_hang TIMESTAMPTZ,
    nhan_vien_giao_id BIGINT,
    nhan_vien_giao_ten VARCHAR,
    diem_danh_gia INTEGER,
    binh_luan_danh_gia TEXT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT
        dh.id, dh.ma_van_don, dh.trang_thai,
        dh.nguoi_gui_ten, dh.nguoi_gui_dia_chi, dh.nguoi_gui_sdt,
        dh.nguoi_nhan_ten, dh.nguoi_nhan_dia_chi, dh.nguoi_nhan_sdt,
        dh.can_nang, dh.gia_tri_hang, dh.phi_van_chuyen, dh.cod,
        dh.khoang_cach_km, dh.phuong_tien, dh.ghi_chu,
        dh.ngay_tao, dh.ngay_lay_hang, dh.ngay_giao_hang,
        nv.id, nv.ho_ten, dg.diem_danh_gia, dg.binh_luan
    FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    LEFT JOIN public.nhan_vien nv ON nv.id = dh.nhan_vien_hien_tai_id
    LEFT JOIN public.danh_gia dg
      ON dg.don_hang_id = dh.id AND dg.khach_hang_id = kh.id
    WHERE kh.auth_user_id = auth.uid()
    ORDER BY dh.ngay_tao DESC;
$$;

DROP FUNCTION IF EXISTS public.danh_gia_shipper_don_hang(BIGINT, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION public.danh_gia_shipper_don_hang(
    p_don_hang_id BIGINT,
    p_diem INTEGER,
    p_binh_luan TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_nhan_vien_id BIGINT;
    v_trang_thai VARCHAR;
BEGIN
    IF p_diem NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION 'Điểm đánh giá phải từ 1 đến 5 sao';
    END IF;

    SELECT dh.khach_hang_id, dh.nhan_vien_hien_tai_id, dh.trang_thai
    INTO v_khach_hang_id, v_nhan_vien_id, v_trang_thai
    FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    WHERE dh.id = p_don_hang_id
      AND kh.auth_user_id = auth.uid();

    IF v_khach_hang_id IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng không tồn tại hoặc không thuộc tài khoản này';
    END IF;
    IF v_trang_thai <> 'DA_GIAO_HANG' THEN
        RAISE EXCEPTION 'Chỉ được đánh giá đơn hàng đã giao thành công';
    END IF;
    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng chưa có nhân viên giao hàng';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.danh_gia dg
        WHERE dg.khach_hang_id = v_khach_hang_id
          AND dg.don_hang_id = p_don_hang_id
    ) THEN
        RAISE EXCEPTION 'Đơn hàng này đã được đánh giá và không thể chỉnh sửa';
    END IF;

    INSERT INTO public.danh_gia(
        khach_hang_id, don_hang_id, nhan_vien_id,
        diem_danh_gia, binh_luan
    ) VALUES (
        v_khach_hang_id, p_don_hang_id, v_nhan_vien_id,
        p_diem, NULLIF(BTRIM(p_binh_luan), '')
    );
END;
$$;

REVOKE ALL ON FUNCTION public.danh_gia_shipper_don_hang(BIGINT, INTEGER, TEXT)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.danh_gia_shipper_don_hang(BIGINT, INTEGER, TEXT)
TO authenticated;


REVOKE ALL ON FUNCTION public.don_hang_cua_khach_hang() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.don_hang_cua_khach_hang() TO authenticated;
NOTIFY pgrst, 'reload schema';

