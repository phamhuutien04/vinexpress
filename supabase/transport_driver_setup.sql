-- VINEXPRESS - Nghiệp vụ tài xế xe tải vận chuyển giữa các kho.

CREATE OR REPLACE FUNCTION public.thong_tin_tai_xe_van_chuyen()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'nhan_vien_id', nv.id,
        'ho_ten', nv.ho_ten,
        'so_dien_thoai', nv.so_dien_thoai,
        'email', nv.email,
        'kho_hang_id', nv.kho_hang_id,
        'xe_id', x.id,
        'bien_so_xe', x.bien_so_xe,
        'tai_trong', x.tai_trong,
        'xe_trang_thai', x.trang_thai
    ) INTO v_result
    FROM public.nhan_vien nv
    LEFT JOIN public.xe x ON x.tai_xe_id = nv.id
       AND x.trang_thai <> 'NGUNG_HOAT_DONG'
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'VAN_CHUYEN'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND nv.trang_thai = 'HOAT_DONG'
    ORDER BY x.id
    LIMIT 1;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Tài khoản không phải tài xế vận chuyển hoặc chưa được duyệt';
    END IF;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.chuyen_xe_cua_tai_xe()
RETURNS TABLE (
    id BIGINT,
    ma_chuyen VARCHAR,
    trang_thai VARCHAR,
    ngay_khoi_hanh TIMESTAMPTZ,
    ngay_du_kien TIMESTAMPTZ,
    ngay_den_thuc_te TIMESTAMPTZ,
    bien_so_xe VARCHAR,
    tai_trong NUMERIC,
    kho_di_ten VARCHAR,
    kho_den_ten VARCHAR,
    so_don_hang BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.nhan_vien nv
        WHERE nv.auth_user_id = auth.uid()
          AND nv.vai_tro = 'VAN_CHUYEN'
          AND nv.trang_thai_duyet = 'DA_DUYET'
          AND nv.trang_thai = 'HOAT_DONG'
    ) THEN
        RAISE EXCEPTION 'Không có quyền xem chuyến xe';
    END IF;

    RETURN QUERY
    SELECT cx.id, cx.ma_chuyen::VARCHAR, cx.trang_thai::VARCHAR,
           cx.ngay_khoi_hanh, cx.ngay_du_kien, cx.ngay_den_thuc_te,
           x.bien_so_xe::VARCHAR, x.tai_trong,
           kd.ten_kho::VARCHAR, kden.ten_kho::VARCHAR,
           (SELECT COUNT(*) FROM public.chi_tiet_chuyen_xe ct
            WHERE ct.chuyen_xe_id = cx.id)::BIGINT
    FROM public.chuyen_xe cx
    JOIN public.xe x ON x.id = cx.xe_id
    JOIN public.nhan_vien nv ON nv.id = x.tai_xe_id
    LEFT JOIN LATERAL (
        SELECT c.kho_di_id FROM public.chuyen_xe_chang c
        WHERE c.chuyen_xe_id = cx.id ORDER BY c.thu_tu_chuyen LIMIT 1
    ) dau ON TRUE
    LEFT JOIN LATERAL (
        SELECT c.kho_den_id FROM public.chuyen_xe_chang c
        WHERE c.chuyen_xe_id = cx.id ORDER BY c.thu_tu_chuyen DESC LIMIT 1
    ) cuoi ON TRUE
    LEFT JOIN public.kho_hang kd ON kd.id = dau.kho_di_id
    LEFT JOIN public.kho_hang kden ON kden.id = cuoi.kho_den_id
    WHERE nv.auth_user_id = auth.uid()
    ORDER BY
        CASE cx.trang_thai
          WHEN 'DANG_DI' THEN 1 WHEN 'DANG_XEP_HANG' THEN 2
          WHEN 'CHO_KHOI_HANH' THEN 3 WHEN 'DA_DEN' THEN 4 ELSE 5
        END,
        cx.ngay_tao DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.cap_nhat_chuyen_xe_tai_xe(
    p_chuyen_xe_id BIGINT,
    p_trang_thai_moi TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trang_thai VARCHAR(30);
    v_xe_id BIGINT;
BEGIN
    SELECT cx.trang_thai, x.id INTO v_trang_thai, v_xe_id
    FROM public.chuyen_xe cx
    JOIN public.xe x ON x.id = cx.xe_id
    JOIN public.nhan_vien nv ON nv.id = x.tai_xe_id
    WHERE cx.id = p_chuyen_xe_id
      AND nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'VAN_CHUYEN'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND nv.trang_thai = 'HOAT_DONG'
    FOR UPDATE OF cx;

    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy chuyến xe được phân công'; END IF;

    IF NOT (
        (v_trang_thai IN ('CHO_KHOI_HANH', 'DANG_XEP_HANG') AND p_trang_thai_moi = 'DANG_DI') OR
        (v_trang_thai = 'DANG_DI' AND p_trang_thai_moi = 'DA_DEN') OR
        (v_trang_thai = 'DA_DEN' AND p_trang_thai_moi = 'DA_HOAN_THANH')
    ) THEN
        RAISE EXCEPTION 'Không thể chuyển trạng thái từ % sang %', v_trang_thai, p_trang_thai_moi;
    END IF;

    UPDATE public.chuyen_xe
    SET trang_thai = p_trang_thai_moi,
        ngay_khoi_hanh = CASE WHEN p_trang_thai_moi = 'DANG_DI'
            THEN COALESCE(ngay_khoi_hanh, NOW()) ELSE ngay_khoi_hanh END,
        ngay_den_thuc_te = CASE WHEN p_trang_thai_moi IN ('DA_DEN', 'DA_HOAN_THANH')
            THEN COALESCE(ngay_den_thuc_te, NOW()) ELSE ngay_den_thuc_te END,
        ngay_cap_nhat = NOW()
    WHERE id = p_chuyen_xe_id;

    UPDATE public.xe SET
        trang_thai = CASE WHEN p_trang_thai_moi = 'DA_HOAN_THANH'
            THEN 'SAN_SANG' ELSE 'DANG_CHAY' END,
        ngay_cap_nhat = NOW()
    WHERE id = v_xe_id;

    IF p_trang_thai_moi = 'DANG_DI' THEN
        UPDATE public.chuyen_xe_chang SET trang_thai = 'DANG_DI',
            ngay_khoi_hanh = COALESCE(ngay_khoi_hanh, NOW()), ngay_cap_nhat = NOW()
        WHERE chuyen_xe_id = p_chuyen_xe_id AND trang_thai = 'CHO_KHOI_HANH';
        UPDATE public.chi_tiet_chuyen_xe SET trang_thai = 'DANG_VAN_CHUYEN'
        WHERE chuyen_xe_id = p_chuyen_xe_id AND trang_thai = 'DA_XEP_HANG';
    ELSIF p_trang_thai_moi IN ('DA_DEN', 'DA_HOAN_THANH') THEN
        UPDATE public.chuyen_xe_chang SET trang_thai = 'DA_DEN',
            ngay_den_thuc_te = COALESCE(ngay_den_thuc_te, NOW()), ngay_cap_nhat = NOW()
        WHERE chuyen_xe_id = p_chuyen_xe_id AND trang_thai = 'DANG_DI';
        IF p_trang_thai_moi = 'DA_HOAN_THANH' THEN
            UPDATE public.chi_tiet_chuyen_xe SET trang_thai = 'DA_DO_HANG',
                ngay_do_hang = COALESCE(ngay_do_hang, NOW())
            WHERE chuyen_xe_id = p_chuyen_xe_id;
        END IF;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.thong_tin_tai_xe_van_chuyen() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.chuyen_xe_cua_tai_xe() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cap_nhat_chuyen_xe_tai_xe(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.thong_tin_tai_xe_van_chuyen() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chuyen_xe_cua_tai_xe() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cap_nhat_chuyen_xe_tai_xe(BIGINT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
