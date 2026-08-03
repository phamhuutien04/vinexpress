-- Chạy trong Supabase Dashboard > SQL Editor sau customer_orders_setup.sql.
-- Bán kính mặc định để shipper thấy/nhận đơn: 10 km.

ALTER TABLE public.nhan_vien
    ADD COLUMN IF NOT EXISTS auth_user_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_nhan_vien_auth_user
    ON public.nhan_vien(auth_user_id)
    WHERE auth_user_id IS NOT NULL;

ALTER TABLE public.nhan_vien
    DROP CONSTRAINT IF EXISTS fk_nhan_vien_auth_user;
ALTER TABLE public.nhan_vien
    ADD CONSTRAINT fk_nhan_vien_auth_user
    FOREIGN KEY (auth_user_id)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.vi_tri_nhan_vien (
    nhan_vien_id BIGINT PRIMARY KEY
        REFERENCES public.nhan_vien(id) ON DELETE CASCADE,
    vi_do DOUBLE PRECISION NOT NULL CHECK (vi_do BETWEEN -90 AND 90),
    kinh_do DOUBLE PRECISION NOT NULL CHECK (kinh_do BETWEEN -180 AND 180),
    do_chinh_xac_met DOUBLE PRECISION,
    dang_truc_tuyen BOOLEAN NOT NULL DEFAULT TRUE,
    thoi_gian_cap_nhat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tu_choi_don_hang_shipper (
    don_hang_id BIGINT NOT NULL
        REFERENCES public.don_hang(id) ON DELETE CASCADE,
    nhan_vien_id BIGINT NOT NULL
        REFERENCES public.nhan_vien(id) ON DELETE CASCADE,
    ly_do TEXT,
    thoi_gian_tu_choi TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (don_hang_id, nhan_vien_id)
);

CREATE OR REPLACE FUNCTION public.khoang_cach_km(
    p_vi_do_1 DOUBLE PRECISION,
    p_kinh_do_1 DOUBLE PRECISION,
    p_vi_do_2 DOUBLE PRECISION,
    p_kinh_do_2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT 6371 * 2 * ASIN(
        SQRT(
            POWER(SIN(RADIANS(p_vi_do_2 - p_vi_do_1) / 2), 2)
            + COS(RADIANS(p_vi_do_1)) * COS(RADIANS(p_vi_do_2))
            * POWER(SIN(RADIANS(p_kinh_do_2 - p_kinh_do_1) / 2), 2)
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.cap_nhat_vi_tri_shipper(
    p_vi_do DOUBLE PRECISION,
    p_kinh_do DOUBLE PRECISION,
    p_do_chinh_xac_met DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
BEGIN
    SELECT nv.id INTO v_nhan_vien_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET';

    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Tài khoản không phải shipper đã được duyệt';
    END IF;

    INSERT INTO public.vi_tri_nhan_vien (
        nhan_vien_id, vi_do, kinh_do, do_chinh_xac_met,
        dang_truc_tuyen, thoi_gian_cap_nhat
    ) VALUES (
        v_nhan_vien_id, p_vi_do, p_kinh_do, p_do_chinh_xac_met,
        TRUE, NOW()
    )
    ON CONFLICT (nhan_vien_id) DO UPDATE SET
        vi_do = EXCLUDED.vi_do,
        kinh_do = EXCLUDED.kinh_do,
        do_chinh_xac_met = EXCLUDED.do_chinh_xac_met,
        dang_truc_tuyen = TRUE,
        thoi_gian_cap_nhat = NOW();
END;
$$;

DROP FUNCTION IF EXISTS public.don_hang_gan_shipper(DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION public.don_hang_gan_shipper(
    p_ban_kinh_km DOUBLE PRECISION DEFAULT 10
)
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    nguoi_gui_ten VARCHAR,
    nguoi_gui_sdt VARCHAR,
    nguoi_gui_dia_chi TEXT,
    nguoi_nhan_dia_chi TEXT,
    nguoi_gui_vi_do DOUBLE PRECISION,
    nguoi_gui_kinh_do DOUBLE PRECISION,
    nguoi_nhan_vi_do DOUBLE PRECISION,
    nguoi_nhan_kinh_do DOUBLE PRECISION,
    can_nang NUMERIC,
    cod NUMERIC,
    khoang_cach_den_diem_lay_km DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
    v_vi_do DOUBLE PRECISION;
    v_kinh_do DOUBLE PRECISION;
BEGIN
    SELECT nv.id, vt.vi_do, vt.kinh_do
    INTO v_nhan_vien_id, v_vi_do, v_kinh_do
    FROM public.nhan_vien nv
    JOIN public.vi_tri_nhan_vien vt ON vt.nhan_vien_id = nv.id
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND vt.dang_truc_tuyen = TRUE
      AND vt.thoi_gian_cap_nhat >= NOW() - INTERVAL '15 minutes';

    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Vui lòng cập nhật vị trí hiện tại trước';
    END IF;

    RETURN QUERY
    SELECT
        dh.id,
        dh.ma_van_don,
        dh.nguoi_gui_ten,
        dh.nguoi_gui_sdt,
        dh.nguoi_gui_dia_chi,
        dh.nguoi_nhan_dia_chi,
        dh.nguoi_gui_vi_do,
        dh.nguoi_gui_kinh_do,
        dh.nguoi_nhan_vi_do,
        dh.nguoi_nhan_kinh_do,
        dh.can_nang,
        dh.cod,
        public.khoang_cach_km(
            v_vi_do, v_kinh_do,
            dh.nguoi_gui_vi_do, dh.nguoi_gui_kinh_do
        ) AS khoang_cach_den_diem_lay_km
    FROM public.don_hang dh
    WHERE dh.trang_thai = 'CHO_LAY_HANG'
      AND dh.phuong_tien = 'XE_MAY'
      AND dh.nhan_vien_hien_tai_id IS NULL
      AND dh.nguoi_gui_vi_do IS NOT NULL
      AND dh.nguoi_gui_kinh_do IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.tu_choi_don_hang_shipper tc
          WHERE tc.don_hang_id = dh.id
            AND tc.nhan_vien_id = v_nhan_vien_id
      )
      AND public.khoang_cach_km(
          v_vi_do, v_kinh_do,
          dh.nguoi_gui_vi_do, dh.nguoi_gui_kinh_do
      ) <= p_ban_kinh_km
    ORDER BY khoang_cach_den_diem_lay_km, dh.ngay_tao;
END;
$$;

CREATE OR REPLACE FUNCTION public.tu_choi_don_hang_gan(
    p_don_hang_id BIGINT,
    p_ly_do TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
BEGIN
    SELECT nv.id INTO v_nhan_vien_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET';

    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Tài khoản không phải shipper đã được duyệt';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.don_hang dh
        WHERE dh.id = p_don_hang_id
          AND dh.trang_thai = 'CHO_LAY_HANG'
          AND dh.nhan_vien_hien_tai_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Đơn hàng không còn khả dụng';
    END IF;

    INSERT INTO public.tu_choi_don_hang_shipper (
        don_hang_id, nhan_vien_id, ly_do
    ) VALUES (
        p_don_hang_id, v_nhan_vien_id, NULLIF(TRIM(p_ly_do), '')
    )
    ON CONFLICT (don_hang_id, nhan_vien_id) DO UPDATE SET
        ly_do = EXCLUDED.ly_do,
        thoi_gian_tu_choi = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.don_hang_dang_giao_cua_shipper()
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    trang_thai VARCHAR,
    nguoi_gui_ten VARCHAR,
    nguoi_gui_sdt VARCHAR,
    nguoi_gui_dia_chi TEXT,
    nguoi_nhan_dia_chi TEXT,
    nguoi_gui_vi_do DOUBLE PRECISION,
    nguoi_gui_kinh_do DOUBLE PRECISION,
    nguoi_nhan_vi_do DOUBLE PRECISION,
    nguoi_nhan_kinh_do DOUBLE PRECISION,
    can_nang NUMERIC,
    cod NUMERIC
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
        dh.nguoi_gui_ten,
        dh.nguoi_gui_sdt,
        dh.nguoi_gui_dia_chi,
        dh.nguoi_nhan_dia_chi,
        dh.nguoi_gui_vi_do,
        dh.nguoi_gui_kinh_do,
        dh.nguoi_nhan_vi_do,
        dh.nguoi_nhan_kinh_do,
        dh.can_nang,
        dh.cod
    FROM public.don_hang dh
    JOIN public.nhan_vien nv
      ON nv.id = dh.nhan_vien_hien_tai_id
    WHERE nv.auth_user_id = auth.uid()
      AND dh.trang_thai IN (
          'CHO_LAY_HANG', 'DA_LAY_HANG', 'GIAO_CHO_SHIPPER', 'DANG_GIAO_HANG'
      )
    ORDER BY dh.ngay_tao DESC;
$$;

CREATE OR REPLACE FUNCTION public.nhan_don_hang_gan(
    p_don_hang_id BIGINT,
    p_ban_kinh_km DOUBLE PRECISION DEFAULT 10
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
    v_vi_do DOUBLE PRECISION;
    v_kinh_do DOUBLE PRECISION;
    v_don public.don_hang%ROWTYPE;
    v_khoang_cach DOUBLE PRECISION;
BEGIN
    SELECT nv.id, vt.vi_do, vt.kinh_do
    INTO v_nhan_vien_id, v_vi_do, v_kinh_do
    FROM public.nhan_vien nv
    JOIN public.vi_tri_nhan_vien vt ON vt.nhan_vien_id = nv.id
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND vt.dang_truc_tuyen = TRUE
      AND vt.thoi_gian_cap_nhat >= NOW() - INTERVAL '15 minutes';

    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Vui lòng cập nhật vị trí hiện tại trước';
    END IF;

    SELECT * INTO v_don
    FROM public.don_hang
    WHERE don_hang.id = p_don_hang_id
    FOR UPDATE;

    IF NOT FOUND OR v_don.trang_thai <> 'CHO_LAY_HANG'
       OR v_don.nhan_vien_hien_tai_id IS NOT NULL
       OR v_don.phuong_tien <> 'XE_MAY' THEN
        RAISE EXCEPTION 'Đơn hàng không còn khả dụng';
    END IF;

    v_khoang_cach := public.khoang_cach_km(
        v_vi_do, v_kinh_do,
        v_don.nguoi_gui_vi_do, v_don.nguoi_gui_kinh_do
    );

    IF v_khoang_cach > p_ban_kinh_km THEN
        RAISE EXCEPTION 'Điểm lấy hàng nằm ngoài bán kính cho phép';
    END IF;

    UPDATE public.don_hang
    SET nhan_vien_hien_tai_id = v_nhan_vien_id
    WHERE don_hang.id = p_don_hang_id;

    INSERT INTO public.nhat_ky_don_hang (
        nhan_vien_id, don_hang_id, khach_hang_id,
        hanh_dong, trang_thai_cu, trang_thai_moi,
        ghi_chu, vi_do, kinh_do
    ) VALUES (
        v_nhan_vien_id, v_don.id, v_don.khach_hang_id,
        'Shipper đã nhận đơn gần vị trí hiện tại',
        v_don.trang_thai, v_don.trang_thai,
        'Khoảng cách đến điểm lấy: ' || ROUND(v_khoang_cach::NUMERIC, 2) || ' km',
        v_vi_do, v_kinh_do
    );

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.cap_nhat_chang_giao_shipper(
    p_don_hang_id BIGINT,
    p_trang_thai_moi TEXT,
    p_vi_do DOUBLE PRECISION DEFAULT NULL,
    p_kinh_do DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
    v_don public.don_hang%ROWTYPE;
    v_trang_thai_moi TEXT := UPPER(BTRIM(p_trang_thai_moi));
BEGIN
    SELECT nv.id INTO v_nhan_vien_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro IN ('SHIPPER', 'VAN_CHUYEN')
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET';

    SELECT * INTO v_don
    FROM public.don_hang dh
    WHERE dh.id = p_don_hang_id
    FOR UPDATE;

    IF v_nhan_vien_id IS NULL OR NOT FOUND
       OR v_don.nhan_vien_hien_tai_id IS DISTINCT FROM v_nhan_vien_id THEN
        RAISE EXCEPTION 'Bạn không được phân công giao đơn hàng này';
    END IF;

    IF v_trang_thai_moi = 'DA_LAY_HANG'
       AND v_don.trang_thai = 'CHO_LAY_HANG' THEN
        UPDATE public.don_hang
        SET trang_thai = 'DA_LAY_HANG', ngay_lay_hang = NOW()
        WHERE id = p_don_hang_id;
    ELSIF v_trang_thai_moi = 'DA_GIAO_HANG'
       AND v_don.trang_thai IN ('DA_LAY_HANG', 'DANG_GIAO_HANG') THEN
        UPDATE public.don_hang
        SET trang_thai = 'DA_GIAO_HANG', ngay_giao_hang = NOW()
        WHERE id = p_don_hang_id;
    ELSE
        RAISE EXCEPTION 'Không thể chuyển từ trạng thái % sang %',
            v_don.trang_thai, v_trang_thai_moi;
    END IF;

    INSERT INTO public.nhat_ky_don_hang (
        nhan_vien_id, don_hang_id, khach_hang_id,
        hanh_dong, trang_thai_cu, trang_thai_moi,
        ghi_chu, vi_do, kinh_do
    ) VALUES (
        v_nhan_vien_id, v_don.id, v_don.khach_hang_id,
        CASE v_trang_thai_moi
            WHEN 'DA_LAY_HANG' THEN 'Shipper đã lấy hàng'
            ELSE 'Shipper đã giao hàng thành công'
        END,
        v_don.trang_thai, v_trang_thai_moi,
        'Cập nhật từ màn hình dẫn đường', p_vi_do, p_kinh_do
    );
END;
$$;

REVOKE ALL ON FUNCTION public.cap_nhat_vi_tri_shipper(
    DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.don_hang_gan_shipper(
    DOUBLE PRECISION
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nhan_don_hang_gan(
    BIGINT, DOUBLE PRECISION
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tu_choi_don_hang_gan(
    BIGINT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cap_nhat_chang_giao_shipper(
    BIGINT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.don_hang_dang_giao_cua_shipper() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.cap_nhat_vi_tri_shipper(
    DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.don_hang_gan_shipper(
    DOUBLE PRECISION
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_don_hang_gan(
    BIGINT, DOUBLE PRECISION
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tu_choi_don_hang_gan(
    BIGINT, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cap_nhat_chang_giao_shipper(
    BIGINT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.don_hang_dang_giao_cua_shipper()
TO authenticated;
