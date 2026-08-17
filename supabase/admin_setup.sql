-- VINEXPRESS - QUYỀN VÀ API QUẢN TRỊ CẤP CAO NHẤT
-- Chạy file này trong Supabase SQL Editor sau employee_auth_setup.sql.

CREATE OR REPLACE FUNCTION public.la_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.nhan_vien nv
        WHERE nv.auth_user_id = auth.uid()
          AND nv.vai_tro = 'ADMIN'
          AND nv.trang_thai_duyet = 'DA_DUYET'
          AND nv.trang_thai = 'HOAT_DONG'
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_tong_quan()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_ket_qua JSONB;
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được truy cập chức năng này';
    END IF;

    SELECT jsonb_build_object(
        'tong_nhan_vien', (
            SELECT COUNT(*) FROM public.nhan_vien
            WHERE auth_user_id IS DISTINCT FROM auth.uid()
        ),
        'nhan_vien_cho_duyet', (
            SELECT COUNT(*) FROM public.nhan_vien
            WHERE trang_thai_duyet = 'CHO_DUYET'
              AND auth_user_id IS DISTINCT FROM auth.uid()
        ),
        'tong_khach_hang', (SELECT COUNT(*) FROM public.khach_hang),
        'tong_don_hang', (SELECT COUNT(*) FROM public.don_hang),
        'don_cho_lay', (
            SELECT COUNT(*) FROM public.don_hang
            WHERE trang_thai = 'CHO_LAY_HANG'
        ),
        'don_dang_giao', (
            SELECT COUNT(*) FROM public.don_hang
            WHERE trang_thai IN (
                'DA_LAY_HANG', 'DANG_VAN_CHUYEN',
                'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG'
            )
        ),
        'don_da_giao', (
            SELECT COUNT(*) FROM public.don_hang
            WHERE trang_thai = 'DA_GIAO_HANG'
        ),
        'tong_doanh_thu_van_chuyen', (
            SELECT COALESCE(SUM(phi_van_chuyen), 0)
            FROM public.don_hang WHERE trang_thai = 'DA_GIAO_HANG'
        )
    ) INTO v_ket_qua;

    RETURN v_ket_qua;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_danh_sach_nhan_vien()
RETURNS TABLE (
    id BIGINT,
    auth_user_id UUID,
    ho_ten VARCHAR,
    so_dien_thoai VARCHAR,
    email VARCHAR,
    vai_tro VARCHAR,
    trang_thai_duyet VARCHAR,
    trang_thai VARCHAR,
    kho_hang_id BIGINT,
    ten_kho VARCHAR,
    ngay_tao TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xem toàn bộ nhân viên';
    END IF;

    RETURN QUERY
    SELECT nv.id, nv.auth_user_id, nv.ho_ten::VARCHAR,
           nv.so_dien_thoai::VARCHAR, nv.email::VARCHAR,
           nv.vai_tro::VARCHAR, nv.trang_thai_duyet::VARCHAR,
           nv.trang_thai::VARCHAR, nv.kho_hang_id,
           kh.ten_kho::VARCHAR, nv.ngay_tao
    FROM public.nhan_vien nv
    LEFT JOIN public.kho_hang kh ON kh.id = nv.kho_hang_id
    -- Tài khoản Admin vẫn nằm trong bảng nhan_vien. Chỉ không lặp lại
    -- chính tài khoản đang đăng nhập trong danh sách nhân sự cần quản lý.
    WHERE nv.auth_user_id IS DISTINCT FROM auth.uid()
    ORDER BY
        CASE WHEN nv.trang_thai_duyet = 'CHO_DUYET' THEN 0 ELSE 1 END,
        nv.ngay_tao DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_danh_sach_khach_hang()
RETURNS TABLE (
    id BIGINT,
    ho_ten VARCHAR,
    so_dien_thoai VARCHAR,
    email VARCHAR,
    dia_chi TEXT,
    trang_thai VARCHAR,
    ngay_tao TIMESTAMPTZ,
    tong_don BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xem toàn bộ khách hàng';
    END IF;

    RETURN QUERY
    SELECT kh.id, kh.ho_ten::VARCHAR, kh.so_dien_thoai::VARCHAR,
           kh.email::VARCHAR, kh.dia_chi, kh.trang_thai::VARCHAR,
           kh.ngay_tao, COUNT(dh.id)::BIGINT
    FROM public.khach_hang kh
    LEFT JOIN public.don_hang dh ON dh.khach_hang_id = kh.id
    GROUP BY kh.id
    ORDER BY kh.ngay_tao DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_danh_sach_don_hang()
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    trang_thai VARCHAR,
    khach_hang_ten VARCHAR,
    nguoi_gui_dia_chi TEXT,
    nguoi_nhan_ten VARCHAR,
    nguoi_nhan_dia_chi TEXT,
    phi_van_chuyen NUMERIC,
    cod NUMERIC,
    shipper_ten VARCHAR,
    ngay_tao TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xem toàn bộ đơn hàng';
    END IF;

    RETURN QUERY
    SELECT dh.id, dh.ma_van_don::VARCHAR, dh.trang_thai::VARCHAR,
           kh.ho_ten::VARCHAR, dh.nguoi_gui_dia_chi,
           dh.nguoi_nhan_ten::VARCHAR,
           dh.nguoi_nhan_dia_chi, dh.phi_van_chuyen, dh.cod,
           nv.ho_ten::VARCHAR, dh.ngay_tao
    FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    LEFT JOIN public.nhan_vien nv ON nv.id = dh.nhan_vien_hien_tai_id
    ORDER BY dh.ngay_tao DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_danh_sach_kho()
RETURNS TABLE (
    id BIGINT,
    ma_kho VARCHAR,
    ten_kho VARCHAR,
    dia_chi TEXT,
    so_dien_thoai VARCHAR,
    trang_thai VARCHAR,
    cap_kho SMALLINT,
    kho_trung_tam_id BIGINT,
    ten_kho_trung_tam VARCHAR,
    khu_vuc_id BIGINT,
    tinh_thanh VARCHAR,
    phuong_xa VARCHAR,
    ngay_tao TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xem danh sách kho';
    END IF;

    RETURN QUERY
    SELECT kh.id, kh.ma_kho::VARCHAR, kh.ten_kho::VARCHAR, kh.dia_chi,
           kh.so_dien_thoai::VARCHAR, kh.trang_thai::VARCHAR, kh.cap_kho,
           kh.kho_trung_tam_id, trung_tam.ten_kho::VARCHAR, kh.khu_vuc_id,
           kv.tinh_thanh::VARCHAR, kv.phuong_xa::VARCHAR, kh.ngay_tao
    FROM public.kho_hang kh
    JOIN public.khu_vuc kv ON kv.id = kh.khu_vuc_id
    LEFT JOIN public.kho_hang trung_tam ON trung_tam.id = kh.kho_trung_tam_id
    ORDER BY kh.cap_kho, kv.tinh_thanh, kh.ten_kho;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_danh_sach_khu_vuc()
RETURNS TABLE (
    id BIGINT,
    ten_khu_vuc VARCHAR,
    tinh_thanh VARCHAR,
    quan_huyen VARCHAR,
    phuong_xa VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xem danh sách khu vực';
    END IF;

    RETURN QUERY
    SELECT kv.id, kv.ten_khu_vuc::VARCHAR, kv.tinh_thanh::VARCHAR,
           kv.quan_huyen::VARCHAR, kv.phuong_xa::VARCHAR
    FROM public.khu_vuc kv
    ORDER BY kv.tinh_thanh, kv.quan_huyen NULLS FIRST, kv.phuong_xa NULLS FIRST;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_tao_kho(
    TEXT, TEXT, TEXT, BIGINT, TEXT, SMALLINT, BIGINT
);
DROP FUNCTION IF EXISTS public.admin_tao_kho(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, BIGINT
);

CREATE OR REPLACE FUNCTION public.admin_tao_kho(
    p_ten_kho TEXT,
    p_dia_chi TEXT,
    p_tinh_thanh TEXT,
    p_phuong_xa TEXT,
    p_so_dien_thoai TEXT,
    p_cap_kho SMALLINT,
    p_kho_trung_tam_id BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_kho_id BIGINT;
    v_khu_vuc_id BIGINT;
    v_ma_kho TEXT;
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được tạo kho';
    END IF;
    IF NULLIF(BTRIM(p_ten_kho), '') IS NULL
       OR NULLIF(BTRIM(p_dia_chi), '') IS NULL
       OR NULLIF(BTRIM(p_tinh_thanh), '') IS NULL
       OR NULLIF(BTRIM(p_phuong_xa), '') IS NULL THEN
        RAISE EXCEPTION 'Tên kho và địa chỉ hành chính không được để trống';
    END IF;
    IF p_cap_kho NOT IN (1, 2) THEN
        RAISE EXCEPTION 'Cấp kho chỉ được là 1 hoặc 2';
    END IF;
    IF p_cap_kho = 1 AND p_kho_trung_tam_id IS NOT NULL THEN
        RAISE EXCEPTION 'Kho cấp 1 không được chọn kho trung tâm cha';
    END IF;
    IF p_cap_kho = 2 AND p_kho_trung_tam_id IS NULL THEN
        RAISE EXCEPTION 'Kho cấp 2 phải chọn kho cấp 1 trực thuộc';
    END IF;

    SELECT kv.id INTO v_khu_vuc_id
    FROM public.khu_vuc kv
    WHERE LOWER(BTRIM(kv.tinh_thanh)) = LOWER(BTRIM(p_tinh_thanh))
      AND LOWER(BTRIM(COALESCE(kv.phuong_xa, ''))) = LOWER(BTRIM(p_phuong_xa))
    ORDER BY kv.id
    LIMIT 1;

    IF v_khu_vuc_id IS NULL THEN
        INSERT INTO public.khu_vuc (
            ten_khu_vuc, tinh_thanh, quan_huyen, phuong_xa
        ) VALUES (
            BTRIM(p_phuong_xa) || ', ' || BTRIM(p_tinh_thanh),
            BTRIM(p_tinh_thanh), NULL, BTRIM(p_phuong_xa)
        ) RETURNING id INTO v_khu_vuc_id;
    END IF;

    LOOP
        v_ma_kho := 'K' || p_cap_kho::TEXT || '-' ||
            UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', '') FROM 1 FOR 8));
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.kho_hang kh WHERE kh.ma_kho = v_ma_kho
        );
    END LOOP;

    INSERT INTO public.kho_hang (
        ma_kho, ten_kho, dia_chi, khu_vuc_id, so_dien_thoai,
        trang_thai, cap_kho, kho_trung_tam_id
    ) VALUES (
        v_ma_kho, BTRIM(p_ten_kho), BTRIM(p_dia_chi),
        v_khu_vuc_id, NULLIF(BTRIM(p_so_dien_thoai), ''),
        'HOAT_DONG', p_cap_kho, p_kho_trung_tam_id
    )
    RETURNING id INTO v_kho_id;

    RETURN v_kho_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_cap_nhat_nhan_vien(
    p_nhan_vien_id BIGINT,
    p_trang_thai_duyet TEXT DEFAULT NULL,
    p_trang_thai TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_id BIGINT;
BEGIN
    SELECT nv.id INTO v_admin_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'ADMIN'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND nv.trang_thai = 'HOAT_DONG';

    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được cập nhật nhân viên';
    END IF;
    IF p_nhan_vien_id = v_admin_id AND p_trang_thai = 'TAM_KHOA' THEN
        RAISE EXCEPTION 'ADMIN không thể tự khóa tài khoản của mình';
    END IF;
    IF p_trang_thai_duyet IS NOT NULL
       AND p_trang_thai_duyet NOT IN ('CHO_DUYET', 'DA_DUYET', 'TU_CHOI') THEN
        RAISE EXCEPTION 'Trạng thái duyệt không hợp lệ';
    END IF;
    IF p_trang_thai IS NOT NULL
       AND p_trang_thai NOT IN ('HOAT_DONG', 'TAM_KHOA', 'DA_NGHI') THEN
        RAISE EXCEPTION 'Trạng thái tài khoản không hợp lệ';
    END IF;

    UPDATE public.nhan_vien
    SET trang_thai_duyet = COALESCE(p_trang_thai_duyet, trang_thai_duyet),
        trang_thai = COALESCE(p_trang_thai, trang_thai),
        ngay_cap_nhat = NOW()
    WHERE id = p_nhan_vien_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy nhân viên'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.la_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_tong_quan() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_danh_sach_nhan_vien() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_danh_sach_khach_hang() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_danh_sach_don_hang() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_danh_sach_kho() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_danh_sach_khu_vuc() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_tao_kho(
    TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, BIGINT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_cap_nhat_nhan_vien(BIGINT, TEXT, TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.la_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tong_quan() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_nhan_vien() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_khach_hang() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_don_hang() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_kho() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_khu_vuc() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tao_kho(
    TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, BIGINT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cap_nhat_nhan_vien(BIGINT, TEXT, TEXT)
TO authenticated;

-- Chỉ thực hiện một lần để nâng tài khoản quản trị đầu tiên:
-- UPDATE public.nhan_vien
-- SET vai_tro = 'ADMIN', trang_thai_duyet = 'DA_DUYET', trang_thai = 'HOAT_DONG'
-- WHERE email = 'email-admin-cua-ban@example.com';

NOTIFY pgrst, 'reload schema';
