-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor.
-- <= 50 km: giao trực tiếp bằng xe máy, không cần kho.
-- > 50 km: bắt buộc địa chỉ gửi và nhận phải có kho hoạt động.

CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE TABLE IF NOT EXISTS public.phi_van_chuyen (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    phi_van_chuyen NUMERIC(14,2) NOT NULL DEFAULT 5000
        CHECK (phi_van_chuyen >= 0),
    phan_tram_san NUMERIC(5,2) NOT NULL DEFAULT 20
        CHECK (phan_tram_san BETWEEN 0 AND 100),
    ngay_cap_nhat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.phi_van_chuyen
    ADD COLUMN IF NOT EXISTS phi_van_chuyen NUMERIC(14,2)
        NOT NULL DEFAULT 5000 CHECK (phi_van_chuyen >= 0);

ALTER TABLE public.phi_van_chuyen
    ADD COLUMN IF NOT EXISTS phan_tram_san NUMERIC(5,2)
        NOT NULL DEFAULT 20 CHECK (phan_tram_san BETWEEN 0 AND 100);

INSERT INTO public.phi_van_chuyen (
    id, phi_van_chuyen, phan_tram_san
) VALUES (1, 5000, 20)
ON CONFLICT (id) DO NOTHING;

-- Chỉ quản trị viên/service role được sửa trực tiếp trong Table Editor.
REVOKE ALL ON TABLE public.phi_van_chuyen FROM anon, authenticated;

DROP FUNCTION IF EXISTS public.lay_phi_van_chuyen_xe_may();

CREATE OR REPLACE FUNCTION public.lay_phi_van_chuyen_xe_may()
RETURNS TABLE (
    phi_van_chuyen NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT ch.phi_van_chuyen
    FROM public.phi_van_chuyen ch
    WHERE ch.id = 1;
$$;

ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS khoang_cach_km NUMERIC(12,2);

ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS phuong_tien VARCHAR(30);

ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS nguoi_gui_vi_do DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS nguoi_gui_kinh_do DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS nguoi_nhan_vi_do DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS nguoi_nhan_kinh_do DOUBLE PRECISION;

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

DROP FUNCTION IF EXISTS public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC,
    DOUBLE PRECISION, DOUBLE PRECISION,
    DOUBLE PRECISION, DOUBLE PRECISION, TEXT
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
    p_nguoi_gui_vi_do DOUBLE PRECISION,
    p_nguoi_gui_kinh_do DOUBLE PRECISION,
    p_nguoi_nhan_vi_do DOUBLE PRECISION,
    p_nguoi_nhan_kinh_do DOUBLE PRECISION,
    p_ghi_chu TEXT DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    ma_qr UUID,
    trang_thai VARCHAR,
    khoang_cach_km NUMERIC,
    phuong_tien VARCHAR,
    phi_van_chuyen NUMERIC,
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
    v_phi_van_chuyen NUMERIC;
    v_phi_moi_km NUMERIC;
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

    SELECT ch.phi_van_chuyen
    INTO v_phi_moi_km
    FROM public.phi_van_chuyen ch
    WHERE ch.id = 1;

    IF v_phi_moi_km IS NULL THEN
        RAISE EXCEPTION 'Chưa cấu hình phí vận chuyển xe máy';
    END IF;

    IF p_khoang_cach_km <= 50 THEN
        v_phuong_tien := 'XE_MAY';
        v_phi_van_chuyen := ROUND(p_khoang_cach_km * v_phi_moi_km, 0);
    ELSE
        v_phuong_tien := 'XE_TAI';
        v_phi_van_chuyen := 30000;
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
        nguoi_gui_vi_do,
        nguoi_gui_kinh_do,
        nguoi_nhan_vi_do,
        nguoi_nhan_kinh_do,
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
        v_phi_van_chuyen,
        GREATEST(p_cod, 0),
        v_kho_gui_id,
        v_kho_dich_id,
        v_kho_trung_tam_gui_id,
        v_kho_trung_tam_dich_id,
        ROUND(p_khoang_cach_km, 2),
        v_phuong_tien,
        p_nguoi_gui_vi_do,
        p_nguoi_gui_kinh_do,
        p_nguoi_nhan_vi_do,
        p_nguoi_nhan_kinh_do,
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
        don_hang.phi_van_chuyen,
        don_hang.ngay_tao;
END;
$$;

REVOKE ALL ON FUNCTION public.tim_kho_theo_dia_chi(
    TEXT, BIGINT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.lay_phi_van_chuyen_xe_may() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lay_phi_van_chuyen_xe_may() TO authenticated;

REVOKE ALL ON FUNCTION public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC,
    DOUBLE PRECISION, DOUBLE PRECISION,
    DOUBLE PRECISION, DOUBLE PRECISION, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC,
    DOUBLE PRECISION, DOUBLE PRECISION,
    DOUBLE PRECISION, DOUBLE PRECISION, TEXT
) TO authenticated;

REVOKE ALL ON FUNCTION public.don_hang_cua_khach_hang() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.don_hang_cua_khach_hang() TO authenticated;

-- Khách chỉ được hủy khi đơn vẫn chờ lấy và chưa có shipper nhận.
DROP FUNCTION IF EXISTS public.huy_don_hang_khach_hang(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.huy_don_hang_khach_hang(
    p_don_hang_id BIGINT,
    p_ly_do TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_don public.don_hang%ROWTYPE;
BEGIN
    SELECT dh.* INTO v_don
    FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    WHERE dh.id = p_don_hang_id
      AND kh.auth_user_id = auth.uid()
    FOR UPDATE OF dh;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Đơn hàng không tồn tại hoặc không thuộc tài khoản này';
    END IF;

    IF v_don.trang_thai <> 'CHO_LAY_HANG'
       OR v_don.nhan_vien_hien_tai_id IS NOT NULL THEN
        RAISE EXCEPTION 'Không thể hủy vì shipper đã nhận đơn hoặc đơn không còn chờ lấy hàng';
    END IF;

    UPDATE public.don_hang
    SET trang_thai = 'DA_HUY',
        ghi_chu = CONCAT_WS(
            E'\n', NULLIF(BTRIM(v_don.ghi_chu), ''),
            'Khách hàng hủy đơn' || CASE
                WHEN NULLIF(BTRIM(p_ly_do), '') IS NULL THEN ''
                ELSE ': ' || BTRIM(p_ly_do)
            END
        ),
        ngay_cap_nhat = NOW()
    WHERE id = p_don_hang_id;

    -- Bảng lời mời được tạo bởi phần phân đơn shipper. Dynamic SQL giúp
    -- migration này vẫn chạy được nếu phần phân đơn chưa được cài.
    IF to_regclass('public.loi_moi_don_hang_shipper') IS NOT NULL THEN
        EXECUTE $sql$
            UPDATE public.loi_moi_don_hang_shipper
            SET trang_thai = 'HET_HAN', phan_hoi_luc = NOW()
            WHERE don_hang_id = $1 AND trang_thai = 'DANG_MOI'
        $sql$ USING p_don_hang_id;
    END IF;

    INSERT INTO public.nhat_ky_don_hang (
        don_hang_id, khach_hang_id, hanh_dong,
        trang_thai_cu, trang_thai_moi, ghi_chu
    ) VALUES (
        v_don.id, v_don.khach_hang_id, 'Khách hàng hủy đơn',
        v_don.trang_thai, 'DA_HUY', NULLIF(BTRIM(p_ly_do), '')
    );
END;
$$;

REVOKE ALL ON FUNCTION public.huy_don_hang_khach_hang(BIGINT, TEXT)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.huy_don_hang_khach_hang(BIGINT, TEXT)
TO authenticated;
NOTIFY pgrst, 'reload schema';

-- CAU HINH PHI XE TAI TRONG BANG PHI VAN CHUYEN
-- Đơn trên 50 km dùng xe tải và lấy phí từ bảng phi_van_chuyen.
-- Chạy an toàn, không xóa dữ liệu.

ALTER TABLE public.phi_van_chuyen
ADD COLUMN IF NOT EXISTS phi_xe_tai NUMERIC(14,2)
  NOT NULL DEFAULT 30000 CHECK(phi_xe_tai>=0);

UPDATE public.phi_van_chuyen
SET phi_xe_tai=COALESCE(phi_xe_tai,30000)
WHERE id=1;

CREATE OR REPLACE FUNCTION public.lay_cau_hinh_phi_van_chuyen()
RETURNS JSONB LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT jsonb_build_object(
    'phi_xe_may_moi_km',COALESCE(pvc.phi_van_chuyen,5000),
    'phi_xe_tai',COALESCE(pvc.phi_xe_tai,30000),
    'phan_tram_san',COALESCE(pvc.phan_tram_san,20)
  )
  FROM public.phi_van_chuyen pvc WHERE pvc.id=1;
$$;

CREATE OR REPLACE FUNCTION public.ap_dung_phi_mac_dinh_xe_tai()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_phi_xe_tai NUMERIC;
BEGIN
  IF NEW.phuong_tien='XE_TAI' AND NEW.khoang_cach_km>50 THEN
    SELECT pvc.phi_xe_tai INTO v_phi_xe_tai
    FROM public.phi_van_chuyen pvc WHERE pvc.id=1;
    NEW.phi_van_chuyen := COALESCE(v_phi_xe_tai,30000);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_phi_mac_dinh_xe_tai ON public.don_hang;
CREATE TRIGGER trg_phi_mac_dinh_xe_tai
BEFORE INSERT OR UPDATE OF phuong_tien,khoang_cach_km,phi_van_chuyen
ON public.don_hang FOR EACH ROW
EXECUTE FUNCTION public.ap_dung_phi_mac_dinh_xe_tai();

REVOKE ALL ON FUNCTION public.lay_cau_hinh_phi_van_chuyen() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lay_cau_hinh_phi_van_chuyen() TO authenticated;

NOTIFY pgrst,'reload schema';

-- ============================================================
-- BẢN CẬP NHẬT PHÍ XE TẢI THEO CÂN NẶNG (3.000Đ/KG NGUYÊN)
-- ============================================================
-- Đơn trên 50 km dùng xe tải và lấy phí từ bảng phi_van_chuyen.
-- Chạy an toàn, không xóa dữ liệu.

ALTER TABLE public.phi_van_chuyen
ADD COLUMN IF NOT EXISTS phi_xe_tai NUMERIC(14,2)
  NOT NULL DEFAULT 30000 CHECK(phi_xe_tai>=0);

ALTER TABLE public.phi_van_chuyen
ADD COLUMN IF NOT EXISTS phi_moi_kg NUMERIC(14,2)
  NOT NULL DEFAULT 3000 CHECK(phi_moi_kg>=0);

-- Giá trị DEFAULT tự được áp dụng cho cả dữ liệu hiện có.

CREATE OR REPLACE FUNCTION public.lay_cau_hinh_phi_van_chuyen()
RETURNS JSONB LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT jsonb_build_object(
    'phi_xe_may_moi_km',COALESCE(pvc.phi_van_chuyen,5000),
    'phi_xe_tai',COALESCE(pvc.phi_xe_tai,30000),
    'phi_moi_kg',COALESCE(pvc.phi_moi_kg,3000),
    'phan_tram_san',COALESCE(pvc.phan_tram_san,20)
  )
  FROM public.phi_van_chuyen pvc WHERE pvc.id=1;
$$;

CREATE OR REPLACE FUNCTION public.ap_dung_phi_mac_dinh_xe_tai()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$
DECLARE
  v_phi_xe_tai NUMERIC;
  v_phi_moi_kg NUMERIC;
  v_so_kg_tinh_phi BIGINT;
BEGIN
  IF NEW.phuong_tien='XE_TAI' AND NEW.khoang_cach_km>50 THEN
    SELECT pvc.phi_xe_tai,pvc.phi_moi_kg
    INTO v_phi_xe_tai,v_phi_moi_kg
    FROM public.phi_van_chuyen pvc WHERE pvc.id=1;
    v_so_kg_tinh_phi := CASE
      WHEN COALESCE(NEW.can_nang,0)<1 THEN 0
      ELSE FLOOR(NEW.can_nang)::BIGINT
    END;
    NEW.phi_van_chuyen := COALESCE(v_phi_xe_tai,30000)
      + v_so_kg_tinh_phi*COALESCE(v_phi_moi_kg,3000);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_phi_mac_dinh_xe_tai ON public.don_hang;
CREATE TRIGGER trg_phi_mac_dinh_xe_tai
BEFORE INSERT OR UPDATE OF phuong_tien,khoang_cach_km,phi_van_chuyen,can_nang
ON public.don_hang FOR EACH ROW
EXECUTE FUNCTION public.ap_dung_phi_mac_dinh_xe_tai();

REVOKE ALL ON FUNCTION public.lay_cau_hinh_phi_van_chuyen() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lay_cau_hinh_phi_van_chuyen() TO authenticated;

NOTIFY pgrst,'reload schema';
