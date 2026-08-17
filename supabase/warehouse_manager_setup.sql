-- VINEXPRESS - Quản lý kho chỉ được xem dữ liệu của kho được phân công.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_tong_quan()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_nhan_vien public.nhan_vien%ROWTYPE;
    v_kho public.kho_hang%ROWTYPE;
BEGIN
    SELECT * INTO v_nhan_vien FROM public.nhan_vien
    WHERE auth_user_id = auth.uid()
      AND vai_tro = 'QUAN_LY_KHO'
      AND trang_thai_duyet = 'DA_DUYET'
      AND trang_thai = 'HOAT_DONG';
    IF NOT FOUND THEN RAISE EXCEPTION 'Tài khoản không có quyền quản lý kho'; END IF;
    IF v_nhan_vien.kho_hang_id IS NULL THEN RAISE EXCEPTION 'Quản lý chưa được gán kho'; END IF;

    SELECT * INTO v_kho FROM public.kho_hang WHERE id = v_nhan_vien.kho_hang_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kho được phân công không tồn tại'; END IF;

    RETURN jsonb_build_object(
        'quan_ly_id', v_nhan_vien.id,
        'quan_ly_ten', v_nhan_vien.ho_ten,
        'kho_id', v_kho.id,
        'ma_kho', v_kho.ma_kho,
        'ten_kho', v_kho.ten_kho,
        'dia_chi', v_kho.dia_chi,
        'don_tai_kho', (SELECT COUNT(*) FROM public.don_hang dh WHERE dh.kho_hien_tai_id = v_kho.id),
        'don_cho_xu_ly', (SELECT COUNT(*) FROM public.don_hang dh
            WHERE (dh.kho_gui_id = v_kho.id OR dh.kho_dich_id = v_kho.id OR dh.kho_hien_tai_id = v_kho.id)
              AND dh.trang_thai IN ('DA_LAY_HANG', 'DEN_KHO_TRUNG_CHUYEN', 'DEN_KHO_DICH')),
        'dang_van_chuyen', (SELECT COUNT(*) FROM public.don_hang dh
            WHERE (dh.kho_gui_id = v_kho.id OR dh.kho_dich_id = v_kho.id)
              AND dh.trang_thai = 'DANG_VAN_CHUYEN'),
        'da_giao', (SELECT COUNT(*) FROM public.don_hang dh
            WHERE (dh.kho_gui_id = v_kho.id OR dh.kho_dich_id = v_kho.id)
              AND dh.trang_thai = 'DA_GIAO_HANG')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_don()
RETURNS TABLE (
    id BIGINT,
    ma_van_don VARCHAR,
    nguoi_gui_ten VARCHAR,
    nguoi_nhan_ten VARCHAR,
    can_nang NUMERIC,
    trang_thai VARCHAR,
    kho_hien_tai_id BIGINT,
    ngay_tao TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_kho_id BIGINT;
BEGIN
    SELECT nv.kho_hang_id INTO v_kho_id FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'QUAN_LY_KHO'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND nv.trang_thai = 'HOAT_DONG';
    IF v_kho_id IS NULL THEN RAISE EXCEPTION 'Quản lý chưa được gán kho'; END IF;

    RETURN QUERY
    SELECT dh.id, dh.ma_van_don::VARCHAR, dh.nguoi_gui_ten::VARCHAR,
           dh.nguoi_nhan_ten::VARCHAR, dh.can_nang, dh.trang_thai::VARCHAR,
           dh.kho_hien_tai_id, dh.ngay_tao
    FROM public.don_hang dh
    WHERE dh.kho_gui_id = v_kho_id
       OR dh.kho_dich_id = v_kho_id
       OR dh.kho_hien_tai_id = v_kho_id
    ORDER BY dh.ngay_cap_nhat DESC
    LIMIT 300;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_nhan_vien()
RETURNS TABLE (
    id BIGINT,
    ho_ten VARCHAR,
    so_dien_thoai VARCHAR,
    email VARCHAR,
    vai_tro VARCHAR,
    trang_thai_duyet VARCHAR,
    trang_thai VARCHAR,
    bien_so_xe VARCHAR,
    tai_trong NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_kho_id BIGINT;
BEGIN
    SELECT nv.kho_hang_id INTO v_kho_id FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'QUAN_LY_KHO'
      AND nv.trang_thai_duyet = 'DA_DUYET'
      AND nv.trang_thai = 'HOAT_DONG';
    IF v_kho_id IS NULL THEN RAISE EXCEPTION 'Quản lý chưa được gán kho'; END IF;

    RETURN QUERY
    SELECT nv.id, nv.ho_ten::VARCHAR, nv.so_dien_thoai::VARCHAR,
           nv.email::VARCHAR, nv.vai_tro::VARCHAR,
           nv.trang_thai_duyet::VARCHAR, nv.trang_thai::VARCHAR,
           x.bien_so_xe::VARCHAR, x.tai_trong
    FROM public.nhan_vien nv
    LEFT JOIN public.xe x ON x.tai_xe_id = nv.id
    WHERE nv.kho_hang_id = v_kho_id
      AND nv.auth_user_id IS DISTINCT FROM auth.uid()
      AND nv.vai_tro IN ('QUAN_LY_KHO', 'NHAN_VIEN_KHO', 'VAN_CHUYEN')
    ORDER BY nv.ngay_tao DESC;
END;
$$;

-- Phạm vi: quản lý kho cấp 1 được quản lý chính kho đó và mọi kho cấp 2
-- trực thuộc; quản lý kho cấp 2 chỉ được quản lý chính kho của mình.
CREATE OR REPLACE FUNCTION public.quan_ly_kho_danh_sach_kho()
RETURNS TABLE (
    id BIGINT,
    ma_kho VARCHAR,
    ten_kho VARCHAR,
    dia_chi TEXT,
    cap_kho SMALLINT,
    kho_trung_tam_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_kho_id BIGINT;
    v_cap_kho SMALLINT;
BEGIN
    SELECT nv.kho_hang_id INTO v_kho_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid() AND nv.vai_tro = 'QUAN_LY_KHO'
      AND nv.trang_thai_duyet = 'DA_DUYET' AND nv.trang_thai = 'HOAT_DONG';
    IF v_kho_id IS NULL THEN RAISE EXCEPTION 'Quản lý chưa được gán kho'; END IF;
    SELECT kh.cap_kho INTO v_cap_kho FROM public.kho_hang kh WHERE kh.id = v_kho_id;

    RETURN QUERY
    SELECT kh.id, kh.ma_kho::VARCHAR, kh.ten_kho::VARCHAR, kh.dia_chi,
           kh.cap_kho, kh.kho_trung_tam_id
    FROM public.kho_hang kh
    WHERE kh.id = v_kho_id
       OR (v_cap_kho = 1 AND kh.kho_trung_tam_id = v_kho_id)
    ORDER BY kh.cap_kho, kh.ten_kho;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_duoc_quan_ly(p_kho_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.quan_ly_kho_danh_sach_kho() k
        WHERE k.id = p_kho_id
    );
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_tong_quan_theo_kho(p_kho_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_kho public.kho_hang%ROWTYPE;
    v_quan_ly_ten TEXT;
BEGIN
    IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
        RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
    END IF;
    SELECT * INTO v_kho FROM public.kho_hang WHERE id = p_kho_id;
    SELECT nv.ho_ten INTO v_quan_ly_ten FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid();
    RETURN jsonb_build_object(
        'quan_ly_ten', v_quan_ly_ten, 'kho_id', v_kho.id,
        'ma_kho', v_kho.ma_kho, 'ten_kho', v_kho.ten_kho,
        'dia_chi', v_kho.dia_chi, 'cap_kho', v_kho.cap_kho,
        'don_tai_kho', (SELECT COUNT(*) FROM public.don_hang dh WHERE dh.kho_hien_tai_id = v_kho.id),
        'don_cho_xu_ly', (SELECT COUNT(*) FROM public.don_hang dh WHERE
            (dh.kho_gui_id = v_kho.id OR dh.kho_dich_id = v_kho.id OR dh.kho_hien_tai_id = v_kho.id)
            AND dh.trang_thai IN ('DA_LAY_HANG','DEN_KHO_TRUNG_CHUYEN','DEN_KHO_DICH')),
        'dang_van_chuyen', (SELECT COUNT(*) FROM public.don_hang dh WHERE
            (dh.kho_gui_id = v_kho.id OR dh.kho_dich_id = v_kho.id) AND dh.trang_thai = 'DANG_VAN_CHUYEN'),
        'da_giao', (SELECT COUNT(*) FROM public.don_hang dh WHERE
            (dh.kho_gui_id = v_kho.id OR dh.kho_dich_id = v_kho.id) AND dh.trang_thai = 'DA_GIAO_HANG')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_don_theo_kho(p_kho_id BIGINT)
RETURNS SETOF public.don_hang
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
    IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý'; END IF;
    RETURN QUERY SELECT dh.* FROM public.don_hang dh
    WHERE dh.kho_gui_id = p_kho_id OR dh.kho_dich_id = p_kho_id OR dh.kho_hien_tai_id = p_kho_id
    ORDER BY dh.ngay_cap_nhat DESC LIMIT 300;
END;
$$;

CREATE OR REPLACE FUNCTION public.quan_ly_kho_nhan_vien_theo_kho(p_kho_id BIGINT)
RETURNS TABLE (id BIGINT, ho_ten VARCHAR, so_dien_thoai VARCHAR, email VARCHAR,
    vai_tro VARCHAR, trang_thai_duyet VARCHAR, trang_thai VARCHAR,
    bien_so_xe VARCHAR, tai_trong NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
    IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý'; END IF;
    RETURN QUERY SELECT nv.id, nv.ho_ten::VARCHAR, nv.so_dien_thoai::VARCHAR,
        nv.email::VARCHAR, nv.vai_tro::VARCHAR, nv.trang_thai_duyet::VARCHAR,
        nv.trang_thai::VARCHAR, x.bien_so_xe::VARCHAR, x.tai_trong
    FROM public.nhan_vien nv LEFT JOIN public.xe x ON x.tai_xe_id = nv.id
    WHERE nv.kho_hang_id = p_kho_id AND nv.auth_user_id IS DISTINCT FROM auth.uid()
      AND nv.vai_tro IN ('QUAN_LY_KHO','NHAN_VIEN_KHO','VAN_CHUYEN') ORDER BY
        CASE nv.vai_tro WHEN 'QUAN_LY_KHO' THEN 0 WHEN 'NHAN_VIEN_KHO' THEN 1 ELSE 2 END,
        nv.ngay_tao DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_tong_quan() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_don() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_nhan_vien() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_danh_sach_kho() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_duoc_quan_ly(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_tong_quan_theo_kho(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_don_theo_kho(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quan_ly_kho_nhan_vien_theo_kho(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_tong_quan() TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_don() TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_nhan_vien() TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_danh_sach_kho() TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_duoc_quan_ly(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_tong_quan_theo_kho(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_don_theo_kho(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_nhan_vien_theo_kho(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';
