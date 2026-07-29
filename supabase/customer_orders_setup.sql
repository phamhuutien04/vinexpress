-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor.
-- <= 50 km: giao trực tiếp bằng xe máy, không cần kho.
-- > 50 km: bắt buộc địa chỉ gửi và nhận phải có kho hoạt động.

CREATE EXTENSION IF NOT EXISTS unaccent;

ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS khoang_cach_km NUMERIC(12,2);

ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS phuong_tien VARCHAR(30);

-- Lưu các chặng liên tỉnh qua kho trung tâm, tách khỏi kho địa phương
-- (cấp 2) nhận/giao hàng.
ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS kho_trung_tam_gui_id BIGINT
        REFERENCES public.kho_hang(id),
    ADD COLUMN IF NOT EXISTS kho_trung_tam_dich_id BIGINT
        REFERENCES public.kho_hang(id);

ALTER TABLE public.don_hang
    ALTER COLUMN kho_gui_id DROP NOT NULL,
    ALTER COLUMN kho_dich_id DROP NOT NULL;

ALTER TABLE public.don_hang
    DROP CONSTRAINT IF EXISTS chk_don_hang_kho;

ALTER TABLE public.don_hang
    ADD CONSTRAINT chk_don_hang_kho CHECK (
        (
            phuong_tien = 'XE_MAY'
            AND khoang_cach_km <= 50
            AND kho_gui_id IS NULL
            AND kho_dich_id IS NULL
        )
        OR
        (
            phuong_tien = 'XE_TAI'
            AND khoang_cach_km > 50
            AND kho_gui_id IS NOT NULL
            AND kho_dich_id IS NOT NULL
            AND kho_gui_id <> kho_dich_id
            AND kho_trung_tam_gui_id IS NOT NULL
            AND kho_trung_tam_dich_id IS NOT NULL
        )
        OR
        (
            phuong_tien IS NULL
            AND khoang_cach_km IS NULL
        )
    );

ALTER TABLE public.don_hang
    DROP CONSTRAINT IF EXISTS chk_don_hang_phuong_tien;

ALTER TABLE public.don_hang
    ADD CONSTRAINT chk_don_hang_phuong_tien CHECK (
        phuong_tien IS NULL OR phuong_tien IN ('XE_MAY', 'XE_TAI')
    );

CREATE OR REPLACE FUNCTION public.tim_kho_theo_dia_chi(
    p_dia_chi TEXT,
    p_kho_bo_qua BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_dia_chi TEXT;
    v_kho_id BIGINT;
BEGIN
    v_dia_chi := public.unaccent(LOWER(COALESCE(p_dia_chi, '')));

    SELECT kh.id
    INTO v_kho_id
    FROM public.kho_hang AS kh
    JOIN public.khu_vuc AS kv
        ON kv.id = kh.khu_vuc_id
    WHERE kh.trang_thai = 'HOAT_DONG'
      AND kv.tinh_thanh IS NOT NULL
      AND kv.phuong_xa IS NOT NULL
      AND v_dia_chi LIKE
          '%' || public.unaccent(LOWER(BTRIM(kv.tinh_thanh))) || '%'
      AND v_dia_chi LIKE
          '%' || public.unaccent(LOWER(BTRIM(kv.phuong_xa))) || '%'
      AND (p_kho_bo_qua IS NULL OR kh.id <> p_kho_bo_qua)
    ORDER BY kh.id
    LIMIT 1;

    IF v_kho_id IS NULL THEN
        RAISE EXCEPTION
            'Tỉnh/thành hoặc phường/xã trong địa chỉ này chưa có kho hoạt động: %',
            p_dia_chi;
    END IF;

    RETURN v_kho_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.tim_kho_trung_tam(
    p_kho_id BIGINT
)
RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT CASE
        WHEN cap_kho = 1 THEN id
        WHEN cap_kho = 2 THEN kho_trung_tam_id
    END
    FROM public.kho_hang
    WHERE id = p_kho_id
      AND trang_thai = 'HOAT_DONG';
$$;

DROP FUNCTION IF EXISTS public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC,
    BIGINT, BIGINT, TEXT
);

DROP FUNCTION IF EXISTS public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT
);

CREATE OR REPLACE FUNCTION public.tao_don_hang_khach_hang(
    p_nguoi_gui_ten TEXT,
    p_nguoi_gui_dia_chi TEXT,
    p_nguoi_gui_sdt TEXT,
    p_nguoi_nhan_ten TEXT,
    p_nguoi_nhan_dia_chi TEXT,
    p_nguoi_nhan_sdt TEXT,
    p_can_nang NUMERIC,
    p_gia_tri_hang NUMERIC,
    p_phi_van_chuyen NUMERIC,
    p_cod NUMERIC,
    p_khoang_cach_km NUMERIC,
    p_ghi_chu TEXT DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    ma_qr UUID,
    trang_thai VARCHAR,
    khoang_cach_km NUMERIC,
    phuong_tien VARCHAR,
    ngay_tao TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_kho_gui_id BIGINT := NULL;
    v_kho_dich_id BIGINT := NULL;
    v_kho_trung_tam_gui_id BIGINT := NULL;
    v_kho_trung_tam_dich_id BIGINT := NULL;
    v_phuong_tien VARCHAR(30);
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Bạn chưa đăng nhập';
    END IF;

    SELECT kh.id
    INTO v_khach_hang_id
    FROM public.khach_hang AS kh
    WHERE kh.auth_user_id = auth.uid()
      AND kh.trang_thai = 'HOAT_DONG';

    IF v_khach_hang_id IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy tài khoản khách hàng đang hoạt động';
    END IF;

    IF p_can_nang <= 0 THEN
        RAISE EXCEPTION 'Khối lượng phải lớn hơn 0';
    END IF;

    IF p_khoang_cach_km IS NULL OR p_khoang_cach_km < 0 THEN
        RAISE EXCEPTION 'Khoảng cách giao hàng không hợp lệ';
    END IF;

    IF p_khoang_cach_km <= 50 THEN
        v_phuong_tien := 'XE_MAY';
    ELSE
        v_phuong_tien := 'XE_TAI';
        v_kho_gui_id := public.tim_kho_theo_dia_chi(p_nguoi_gui_dia_chi);
        v_kho_dich_id := public.tim_kho_theo_dia_chi(
            p_nguoi_nhan_dia_chi,
            v_kho_gui_id
        );
        v_kho_trung_tam_gui_id := public.tim_kho_trung_tam(v_kho_gui_id);
        v_kho_trung_tam_dich_id := public.tim_kho_trung_tam(v_kho_dich_id);

        IF v_kho_trung_tam_gui_id IS NULL
           OR v_kho_trung_tam_dich_id IS NULL THEN
            RAISE EXCEPTION 'Kho địa phương chưa được gán kho trung tâm';
        END IF;
    END IF;

    RETURN QUERY
    INSERT INTO public.don_hang (
        ma_van_don,
        khach_hang_id,
        nguoi_gui_ten,
        nguoi_gui_dia_chi,
        nguoi_gui_sdt,
        nguoi_nhan_ten,
        nguoi_nhan_dia_chi,
        nguoi_nhan_sdt,
        can_nang,
        gia_tri_hang,
        phi_van_chuyen,
        cod,
        kho_gui_id,
        kho_dich_id,
        kho_trung_tam_gui_id,
        kho_trung_tam_dich_id,
        khoang_cach_km,
        phuong_tien,
        trang_thai,
        ghi_chu
    )
    VALUES (
        'VEX' || UPPER(SUBSTRING(REPLACE(GEN_RANDOM_UUID()::TEXT, '-', '') FROM 1 FOR 12)),
        v_khach_hang_id,
        BTRIM(p_nguoi_gui_ten),
        BTRIM(p_nguoi_gui_dia_chi),
        BTRIM(p_nguoi_gui_sdt),
        BTRIM(p_nguoi_nhan_ten),
        BTRIM(p_nguoi_nhan_dia_chi),
        BTRIM(p_nguoi_nhan_sdt),
        p_can_nang,
        GREATEST(p_gia_tri_hang, 0),
        GREATEST(p_phi_van_chuyen, 0),
        GREATEST(p_cod, 0),
        v_kho_gui_id,
        v_kho_dich_id,
        v_kho_trung_tam_gui_id,
        v_kho_trung_tam_dich_id,
        ROUND(p_khoang_cach_km, 2),
        v_phuong_tien,
        'CHO_LAY_HANG',
        NULLIF(BTRIM(p_ghi_chu), '')
    )
    RETURNING
        don_hang.id,
        don_hang.ma_van_don,
        don_hang.ma_qr,
        don_hang.trang_thai,
        don_hang.khoang_cach_km,
        don_hang.phuong_tien,
        don_hang.ngay_tao;
END;
$$;

REVOKE ALL ON FUNCTION public.tim_kho_theo_dia_chi(
    TEXT, BIGINT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT
) TO authenticated;
