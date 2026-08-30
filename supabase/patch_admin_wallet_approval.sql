-- ============================================================
-- ADMIN DUYET NAP / RUT VI
-- Chay file nay trong Supabase SQL Editor sau wallet_shared_setup.sql
-- va patch_wallet_topup_approval.sql. Co the chay lai an toan.
-- ============================================================

DROP FUNCTION IF EXISTS public.admin_danh_sach_yeu_cau_vi(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.admin_danh_sach_yeu_cau_vi(
    p_trang_thai TEXT DEFAULT NULL,
    p_loai TEXT DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    vi_id BIGINT,
    loai VARCHAR,
    so_tien NUMERIC,
    phuong_thuc VARCHAR,
    ngan_hang VARCHAR,
    so_tai_khoan VARCHAR,
    chu_tai_khoan VARCHAR,
    trang_thai VARCHAR,
    ly_do_tu_choi TEXT,
    ngay_tao TIMESTAMPTZ,
    ngay_xu_ly TIMESTAMPTZ,
    loai_chu_vi TEXT,
    chu_vi TEXT,
    email TEXT,
    so_dien_thoai TEXT,
    so_du_hien_tai NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xem yêu cầu nạp/rút ví';
    END IF;
    IF p_trang_thai IS NOT NULL
       AND UPPER(BTRIM(p_trang_thai)) NOT IN ('CHO_DUYET', 'DA_DUYET', 'TU_CHOI') THEN
        RAISE EXCEPTION 'Trạng thái yêu cầu không hợp lệ';
    END IF;
    IF p_loai IS NOT NULL
       AND UPPER(BTRIM(p_loai)) NOT IN ('NAP_TIEN', 'RUT_TIEN') THEN
        RAISE EXCEPTION 'Loại yêu cầu không hợp lệ';
    END IF;

    RETURN QUERY
    SELECT yc.id, yc.vi_id, yc.loai, yc.so_tien, yc.phuong_thuc,
           yc.ngan_hang, yc.so_tai_khoan, yc.chu_tai_khoan,
           yc.trang_thai, yc.ly_do_tu_choi, yc.ngay_tao, yc.ngay_xu_ly,
           CASE WHEN v.khach_hang_id IS NOT NULL
                THEN 'KHACH_HANG'
                ELSE COALESCE(nv.vai_tro::TEXT, 'NHAN_VIEN') END,
           COALESCE(kh.ho_ten::TEXT, nv.ho_ten::TEXT, 'Không rõ'),
           COALESCE(kh.email::TEXT, nv.email::TEXT),
           COALESCE(kh.so_dien_thoai::TEXT, nv.so_dien_thoai::TEXT),
           v.so_du
    FROM public.yeu_cau_nap_rut_vi yc
    JOIN public.vi v ON v.id = yc.vi_id
    LEFT JOIN public.khach_hang kh ON kh.id = v.khach_hang_id
    LEFT JOIN public.nhan_vien nv ON nv.id = v.nhan_vien_id
    WHERE (p_trang_thai IS NULL
           OR yc.trang_thai = UPPER(BTRIM(p_trang_thai)))
      AND (p_loai IS NULL OR yc.loai = UPPER(BTRIM(p_loai)))
    ORDER BY CASE WHEN yc.trang_thai = 'CHO_DUYET' THEN 0 ELSE 1 END,
             yc.ngay_tao DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_xu_ly_yeu_cau_vi(
    p_yeu_cau_id BIGINT,
    p_hanh_dong TEXT,
    p_ly_do TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_yeu_cau public.yeu_cau_nap_rut_vi%ROWTYPE;
    v_hanh_dong TEXT := UPPER(BTRIM(p_hanh_dong));
BEGIN
    IF NOT public.la_admin() THEN
        RAISE EXCEPTION 'Chỉ ADMIN mới được xử lý yêu cầu nạp/rút ví';
    END IF;
    IF v_hanh_dong NOT IN ('DUYET', 'TU_CHOI') THEN
        RAISE EXCEPTION 'Hành động xử lý không hợp lệ';
    END IF;

    SELECT * INTO v_yeu_cau
    FROM public.yeu_cau_nap_rut_vi
    WHERE id = p_yeu_cau_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy yêu cầu ví #%', p_yeu_cau_id;
    END IF;
    IF v_yeu_cau.trang_thai <> 'CHO_DUYET' THEN
        RAISE EXCEPTION 'Yêu cầu này đã được xử lý trước đó';
    END IF;
    IF v_hanh_dong = 'TU_CHOI'
       AND NULLIF(BTRIM(COALESCE(p_ly_do, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Vui lòng nhập lý do từ chối';
    END IF;

    IF v_yeu_cau.loai = 'NAP_TIEN' THEN
        IF v_hanh_dong = 'DUYET' THEN
            -- Ham duyet va trigger hien co dam bao chi cong so du mot lan.
            PERFORM public.duyet_yeu_cau_nap_vi(p_yeu_cau_id);
        ELSE
            UPDATE public.yeu_cau_nap_rut_vi
            SET trang_thai = 'TU_CHOI',
                ly_do_tu_choi = BTRIM(p_ly_do),
                ngay_xu_ly = NOW()
            WHERE id = p_yeu_cau_id;
        END IF;
    ELSIF v_yeu_cau.loai = 'RUT_TIEN' THEN
        IF v_hanh_dong = 'DUYET' THEN
            PERFORM public.duyet_yeu_cau_rut_vi(p_yeu_cau_id);
        ELSE
            -- Ham nay hoan tien tam giu ve vi trong cung transaction.
            PERFORM public.tu_choi_yeu_cau_rut_vi(p_yeu_cau_id, BTRIM(p_ly_do));
        END IF;
    ELSE
        RAISE EXCEPTION 'Loại yêu cầu ví không được hỗ trợ';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_danh_sach_yeu_cau_vi(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_xu_ly_yeu_cau_vi(BIGINT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_yeu_cau_vi(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_xu_ly_yeu_cau_vi(BIGINT, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
