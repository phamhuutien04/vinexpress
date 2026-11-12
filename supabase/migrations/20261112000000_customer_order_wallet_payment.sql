-- Thanh toán phí vận chuyển khi khách tạo đơn: tiền mặt hoặc ví.
-- Nếu chọn ví, tạo đơn và trừ ví phải hoàn tất cùng một giao dịch.

ALTER TABLE public.don_hang
    ADD COLUMN IF NOT EXISTS phuong_thuc_thanh_toan VARCHAR(20)
        NOT NULL DEFAULT 'TIEN_MAT',
    ADD COLUMN IF NOT EXISTS trang_thai_thanh_toan VARCHAR(30)
        NOT NULL DEFAULT 'CHUA_THANH_TOAN';

ALTER TABLE public.don_hang
    DROP CONSTRAINT IF EXISTS chk_don_hang_phuong_thuc_thanh_toan;
ALTER TABLE public.don_hang
    ADD CONSTRAINT chk_don_hang_phuong_thuc_thanh_toan
        CHECK (phuong_thuc_thanh_toan IN ('TIEN_MAT', 'VI'));

ALTER TABLE public.don_hang
    DROP CONSTRAINT IF EXISTS chk_don_hang_trang_thai_thanh_toan;
ALTER TABLE public.don_hang
    ADD CONSTRAINT chk_don_hang_trang_thai_thanh_toan
        CHECK (trang_thai_thanh_toan IN (
            'CHUA_THANH_TOAN', 'DA_THANH_TOAN', 'DA_HOAN_TIEN'
        ));

ALTER TABLE public.giao_dich_vi
    DROP CONSTRAINT IF EXISTS chk_giao_dich_vi_loai;
ALTER TABLE public.giao_dich_vi
    DROP CONSTRAINT IF EXISTS giao_dich_vi_loai_check;
ALTER TABLE public.giao_dich_vi
    ADD CONSTRAINT chk_giao_dich_vi_loai CHECK (loai IN (
        'NAP_TIEN', 'RUT_TIEN', 'YEU_CAU_RUT', 'HOAN_RUT',
        'TRU_COD', 'NHAN_COD', 'TAM_GIU_COD', 'HOAN_COD',
        'THU_NHAP_GIAO_HANG',
        'TRU_PHI_LAY_HANG',
        'THANH_TOAN_DON_HANG', 'HOAN_THANH_TOAN_DON_HANG', 'DIEU_CHINH'
    ));

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
    p_ghi_chu TEXT DEFAULT NULL,
    p_phuong_thuc_thanh_toan TEXT DEFAULT 'TIEN_MAT'
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
    v_phuong_thuc VARCHAR(20);
    v_don public.don_hang%ROWTYPE;
    v_vi_id BIGINT;
    v_so_du NUMERIC;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Bạn chưa đăng nhập';
    END IF;

    SELECT kh.id INTO v_khach_hang_id
    FROM public.khach_hang kh
    WHERE kh.auth_user_id = auth.uid()
      AND kh.trang_thai = 'HOAT_DONG';
    IF v_khach_hang_id IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy tài khoản khách hàng đang hoạt động';
    END IF;

    v_phuong_thuc := UPPER(COALESCE(NULLIF(BTRIM(p_phuong_thuc_thanh_toan), ''), 'TIEN_MAT'));
    IF v_phuong_thuc NOT IN ('TIEN_MAT', 'VI') THEN
        RAISE EXCEPTION 'Phương thức thanh toán không hợp lệ';
    END IF;
    IF p_can_nang <= 0 THEN
        RAISE EXCEPTION 'Khối lượng phải lớn hơn 0';
    END IF;
    IF p_khoang_cach_km IS NULL OR p_khoang_cach_km < 0 THEN
        RAISE EXCEPTION 'Khoảng cách giao hàng không hợp lệ';
    END IF;

    SELECT ch.phi_van_chuyen INTO v_phi_moi_km
    FROM public.phi_van_chuyen ch WHERE ch.id = 1;
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
        v_kho_dich_id := public.tim_kho_theo_dia_chi(p_nguoi_nhan_dia_chi, v_kho_gui_id);
        v_kho_trung_tam_gui_id := public.tim_kho_trung_tam(v_kho_gui_id);
        v_kho_trung_tam_dich_id := public.tim_kho_trung_tam(v_kho_dich_id);
        IF v_kho_trung_tam_gui_id IS NULL OR v_kho_trung_tam_dich_id IS NULL THEN
            RAISE EXCEPTION 'Kho địa phương chưa được gán kho trung tâm';
        END IF;
    END IF;

    IF v_phuong_thuc = 'VI' THEN
        INSERT INTO public.vi(khach_hang_id)
        VALUES (v_khach_hang_id)
        ON CONFLICT (khach_hang_id) DO UPDATE
            SET ngay_cap_nhat = NOW()
        RETURNING id INTO v_vi_id;

        SELECT so_du INTO v_so_du
        FROM public.vi WHERE id = v_vi_id FOR UPDATE;
        IF v_so_du < v_phi_van_chuyen THEN
            RAISE EXCEPTION 'Số dư ví không đủ. Cần %đ, hiện có %đ',
                ROUND(v_phi_van_chuyen), ROUND(v_so_du);
        END IF;
    END IF;

    INSERT INTO public.don_hang (
        ma_van_don, khach_hang_id,
        nguoi_gui_ten, nguoi_gui_dia_chi, nguoi_gui_sdt,
        nguoi_nhan_ten, nguoi_nhan_dia_chi, nguoi_nhan_sdt,
        can_nang, gia_tri_hang, phi_van_chuyen, cod,
        kho_gui_id, kho_dich_id, kho_trung_tam_gui_id, kho_trung_tam_dich_id,
        khoang_cach_km, phuong_tien,
        nguoi_gui_vi_do, nguoi_gui_kinh_do,
        nguoi_nhan_vi_do, nguoi_nhan_kinh_do,
        trang_thai, phuong_thuc_thanh_toan, trang_thai_thanh_toan, ghi_chu
    ) VALUES (
        'VEX' || UPPER(SUBSTRING(REPLACE(GEN_RANDOM_UUID()::TEXT, '-', '') FROM 1 FOR 12)),
        v_khach_hang_id,
        BTRIM(p_nguoi_gui_ten), BTRIM(p_nguoi_gui_dia_chi), BTRIM(p_nguoi_gui_sdt),
        BTRIM(p_nguoi_nhan_ten), BTRIM(p_nguoi_nhan_dia_chi), BTRIM(p_nguoi_nhan_sdt),
        p_can_nang, GREATEST(p_gia_tri_hang, 0), v_phi_van_chuyen, GREATEST(p_cod, 0),
        v_kho_gui_id, v_kho_dich_id, v_kho_trung_tam_gui_id, v_kho_trung_tam_dich_id,
        ROUND(p_khoang_cach_km, 2), v_phuong_tien,
        p_nguoi_gui_vi_do, p_nguoi_gui_kinh_do,
        p_nguoi_nhan_vi_do, p_nguoi_nhan_kinh_do,
        'CHO_LAY_HANG', v_phuong_thuc,
        CASE WHEN v_phuong_thuc = 'VI' THEN 'DA_THANH_TOAN' ELSE 'CHUA_THANH_TOAN' END,
        NULLIF(BTRIM(p_ghi_chu), '')
    ) RETURNING * INTO v_don;

    IF v_phuong_thuc = 'VI' AND v_phi_van_chuyen > 0 THEN
        UPDATE public.vi
        SET so_du = so_du - v_phi_van_chuyen, ngay_cap_nhat = NOW()
        WHERE id = v_vi_id
        RETURNING so_du INTO v_so_du;

        INSERT INTO public.giao_dich_vi(
            vi_id, don_hang_id, loai, so_tien, so_du_sau, noi_dung
        ) VALUES (
            v_vi_id, v_don.id, 'THANH_TOAN_DON_HANG', v_phi_van_chuyen, v_so_du,
            'Thanh toán phí vận chuyển cho đơn ' || v_don.ma_van_don
        );
    END IF;

    RETURN QUERY SELECT
        v_don.id, v_don.ma_van_don, v_don.ma_qr, v_don.trang_thai,
        v_don.khoang_cach_km, v_don.phuong_tien, v_don.phi_van_chuyen,
        v_don.ngay_tao;
END;
$$;

-- Hoàn phí tự động khi bất kỳ luồng nào chuyển đơn đã trả bằng ví sang ĐÃ_HỦY.
-- Trigger giúp bao phủ cả khách tự hủy và hệ thống hủy vì không tìm thấy shipper.
CREATE OR REPLACE FUNCTION public.hoan_tien_vi_khi_huy_don()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_vi_id BIGINT;
    v_so_du_moi NUMERIC;
BEGIN
    IF NEW.trang_thai <> 'DA_HUY'
       OR OLD.trang_thai = 'DA_HUY'
       OR NEW.phuong_thuc_thanh_toan <> 'VI'
       OR NEW.trang_thai_thanh_toan <> 'DA_THANH_TOAN' THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.vi(khach_hang_id)
    VALUES (NEW.khach_hang_id)
    ON CONFLICT (khach_hang_id) DO UPDATE SET ngay_cap_nhat = NOW()
    RETURNING id INTO v_vi_id;

    -- Khoá ví và dùng dòng giao dịch hoàn tiền làm chốt chống hoàn trùng.
    PERFORM 1 FROM public.vi WHERE id = v_vi_id FOR UPDATE;
    IF EXISTS (
        SELECT 1 FROM public.giao_dich_vi gd
        WHERE gd.vi_id = v_vi_id
          AND gd.don_hang_id = NEW.id
          AND gd.loai = 'HOAN_THANH_TOAN_DON_HANG'
    ) THEN
        RETURN NEW;
    END IF;

    IF NEW.phi_van_chuyen > 0 THEN
        UPDATE public.vi
        SET so_du = so_du + NEW.phi_van_chuyen,
            ngay_cap_nhat = NOW()
        WHERE id = v_vi_id
        RETURNING so_du INTO v_so_du_moi;

        INSERT INTO public.giao_dich_vi(
            vi_id, don_hang_id, loai, so_tien, so_du_sau, noi_dung
        ) VALUES (
            v_vi_id, NEW.id, 'HOAN_THANH_TOAN_DON_HANG',
            NEW.phi_van_chuyen, v_so_du_moi,
            'Hoàn phí vận chuyển do đơn ' || NEW.ma_van_don || ' đã hủy'
        );
    END IF;

    UPDATE public.don_hang
    SET trang_thai_thanh_toan = 'DA_HOAN_TIEN'
    WHERE id = NEW.id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hoan_tien_vi_khi_huy_don ON public.don_hang;
CREATE TRIGGER trg_hoan_tien_vi_khi_huy_don
AFTER UPDATE OF trang_thai ON public.don_hang
FOR EACH ROW
EXECUTE FUNCTION public.hoan_tien_vi_khi_huy_don();

REVOKE ALL ON FUNCTION public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC,
    DOUBLE PRECISION, DOUBLE PRECISION,
    DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tao_don_hang_khach_hang(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC,
    DOUBLE PRECISION, DOUBLE PRECISION,
    DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT
) TO authenticated;

NOTIFY pgrst, 'reload schema';
