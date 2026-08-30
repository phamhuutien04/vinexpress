-- VINEXPRESS - Theo dõi xuyên suốt đơn hàng cho khách hàng.
-- Chạy toàn bộ file này trong Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.vi_tri_nhan_vien (
    nhan_vien_id BIGINT PRIMARY KEY REFERENCES public.nhan_vien(id) ON DELETE CASCADE,
    vi_do DOUBLE PRECISION NOT NULL CHECK (vi_do BETWEEN -90 AND 90),
    kinh_do DOUBLE PRECISION NOT NULL CHECK (kinh_do BETWEEN -180 AND 180),
    do_chinh_xac_met DOUBLE PRECISION,
    dang_truc_tuyen BOOLEAN NOT NULL DEFAULT TRUE,
    thoi_gian_cap_nhat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.cap_nhat_vi_tri_tai_xe_van_chuyen(
    p_vi_do DOUBLE PRECISION,
    p_kinh_do DOUBLE PRECISION,
    p_do_chinh_xac_met DOUBLE PRECISION DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nhan_vien_id BIGINT;
BEGIN
    IF p_vi_do NOT BETWEEN 8 AND 24 OR p_kinh_do NOT BETWEEN 102 AND 110 THEN
        RAISE EXCEPTION 'Vị trí tài xế phải nằm trong phạm vi Việt Nam';
    END IF;
    SELECT nv.id INTO v_nhan_vien_id FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid() AND nv.vai_tro = 'VAN_CHUYEN'
      AND nv.trang_thai = 'HOAT_DONG' AND nv.trang_thai_duyet = 'DA_DUYET';
    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Tài khoản không phải tài xế vận chuyển đã được duyệt';
    END IF;
    INSERT INTO public.vi_tri_nhan_vien (
        nhan_vien_id, vi_do, kinh_do, do_chinh_xac_met,
        dang_truc_tuyen, thoi_gian_cap_nhat
    ) VALUES (v_nhan_vien_id, p_vi_do, p_kinh_do, p_do_chinh_xac_met, TRUE, NOW())
    ON CONFLICT (nhan_vien_id) DO UPDATE SET
        vi_do = EXCLUDED.vi_do, kinh_do = EXCLUDED.kinh_do,
        do_chinh_xac_met = EXCLUDED.do_chinh_xac_met,
        dang_truc_tuyen = TRUE, thoi_gian_cap_nhat = NOW();
END;
$$;

DROP FUNCTION IF EXISTS public.theo_doi_don_hang_khach_hang(BIGINT);

CREATE FUNCTION public.theo_doi_don_hang_khach_hang(p_don_hang_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
    v_don public.don_hang%ROWTYPE;
    v_kho public.kho_hang%ROWTYPE;
    v_chuyen RECORD;
    v_nhan_vien RECORD;
    v_lich_su JSONB;
    v_cac_chang JSONB;
    v_che_do TEXT;
    v_vi_do DOUBLE PRECISION;
    v_kinh_do DOUBLE PRECISION;
    v_cap_nhat TIMESTAMPTZ;
    v_vi_tri_ten TEXT;
    v_vi_tri_dia_chi TEXT;
    v_diem_den_ten TEXT;
    v_diem_den_dia_chi TEXT;
    v_diem_den_vi_do DOUBLE PRECISION;
    v_diem_den_kinh_do DOUBLE PRECISION;
BEGIN
    SELECT dh.* INTO v_don FROM public.don_hang dh
    JOIN public.khach_hang kh ON kh.id = dh.khach_hang_id
    WHERE dh.id = p_don_hang_id AND kh.auth_user_id = auth.uid();
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy đơn hàng của bạn'; END IF;

    IF v_don.kho_hien_tai_id IS NOT NULL THEN
        SELECT * INTO v_kho FROM public.kho_hang WHERE id = v_don.kho_hien_tai_id;
    END IF;

    SELECT cx.id, cx.ma_chuyen, cx.trang_thai AS chuyen_trang_thai,
           cx.ngay_khoi_hanh, cx.ngay_du_kien, cx.ngay_den_thuc_te,
           ct.trang_thai AS kien_tren_xe_trang_thai,
           x.bien_so_xe, tx.id AS tai_xe_id, tx.ho_ten AS tai_xe_ten,
           cxc.thu_tu_chuyen, cxc.trang_thai AS chang_trang_thai,
           kd.id AS kho_di_id, kd.ten_kho AS kho_di_ten, kd.dia_chi AS kho_di_dia_chi,
           kden.id AS kho_den_id, kden.ten_kho AS kho_den_ten,
           kden.dia_chi AS kho_den_dia_chi,
           vt.vi_do AS tai_xe_vi_do, vt.kinh_do AS tai_xe_kinh_do,
           vt.thoi_gian_cap_nhat AS tai_xe_cap_nhat_luc
    INTO v_chuyen
    FROM public.chi_tiet_chuyen_xe ct
    JOIN public.chuyen_xe cx ON cx.id = ct.chuyen_xe_id
    JOIN public.xe x ON x.id = cx.xe_id
    LEFT JOIN public.nhan_vien tx ON tx.id = x.tai_xe_id
    LEFT JOIN public.vi_tri_nhan_vien vt ON vt.nhan_vien_id = tx.id
    LEFT JOIN LATERAL (
        SELECT c.* FROM public.chuyen_xe_chang c WHERE c.chuyen_xe_id = cx.id
        ORDER BY CASE c.trang_thai WHEN 'DANG_DI' THEN 0 WHEN 'CHO_KHOI_HANH' THEN 1 ELSE 2 END,
                 c.thu_tu_chuyen DESC LIMIT 1
    ) cxc ON TRUE
    LEFT JOIN public.kho_hang kd ON kd.id = cxc.kho_di_id
    LEFT JOIN public.kho_hang kden ON kden.id = cxc.kho_den_id
    WHERE ct.don_hang_id = v_don.id
    ORDER BY CASE WHEN cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI','DA_DEN') THEN 0 ELSE 1 END,
             cx.ngay_tao DESC LIMIT 1;

    SELECT nv.id, nv.ho_ten, nv.so_dien_thoai, nv.vai_tro,
           vt.vi_do, vt.kinh_do, vt.thoi_gian_cap_nhat
    INTO v_nhan_vien FROM public.nhan_vien nv
    LEFT JOIN public.vi_tri_nhan_vien vt ON vt.nhan_vien_id = nv.id
    WHERE nv.id = v_don.nhan_vien_hien_tai_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'hanh_dong', nk.hanh_dong, 'trang_thai', nk.trang_thai_moi,
        'kho_ten', kh.ten_kho, 'ghi_chu', nk.ghi_chu, 'thoi_gian', nk.thoi_gian
    ) ORDER BY nk.thoi_gian DESC), '[]'::JSONB)
    INTO v_lich_su FROM public.nhat_ky_don_hang nk
    LEFT JOIN public.kho_hang kh ON kh.id = nk.kho_id
    WHERE nk.don_hang_id = v_don.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'chuyen_xe_id', cx.id,
        'ma_chuyen', cx.ma_chuyen,
        'bien_so_xe', x.bien_so_xe,
        'trang_thai', cx.trang_thai,
        'thu_tu_chuyen', c.thu_tu_chuyen,
        'kho_di_ten', kd.ten_kho,
        'kho_di_dia_chi', kd.dia_chi,
        'kho_den_ten', kden.ten_kho,
        'kho_den_dia_chi', kden.dia_chi,
        'ngay_khoi_hanh', COALESCE(c.ngay_khoi_hanh, cx.ngay_khoi_hanh),
        'ngay_den', COALESCE(c.ngay_den_thuc_te, cx.ngay_den_thuc_te),
        'kien_tren_xe_trang_thai', ct.trang_thai
    ) ORDER BY cx.ngay_tao, c.thu_tu_chuyen), '[]'::JSONB)
    INTO v_cac_chang
    FROM public.chi_tiet_chuyen_xe ct
    JOIN public.chuyen_xe cx ON cx.id = ct.chuyen_xe_id
    JOIN public.xe x ON x.id = cx.xe_id
    JOIN public.chuyen_xe_chang c ON c.chuyen_xe_id = cx.id
    JOIN public.kho_hang kd ON kd.id = c.kho_di_id
    JOIN public.kho_hang kden ON kden.id = c.kho_den_id
    WHERE ct.don_hang_id = v_don.id
      AND (
        cx.trang_thai IN ('DANG_DI','DA_DEN','DA_HOAN_THANH')
        OR ct.trang_thai IN ('DANG_VAN_CHUYEN','DA_DO_HANG')
      );

    IF v_chuyen.id IS NOT NULL
       AND v_chuyen.chuyen_trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG','DANG_DI','DA_DEN')
       AND v_chuyen.kien_tren_xe_trang_thai <> 'DA_DO_HANG' THEN
        v_che_do := 'XE_TAI';
        v_vi_do := v_chuyen.tai_xe_vi_do;
        v_kinh_do := v_chuyen.tai_xe_kinh_do;
        v_cap_nhat := v_chuyen.tai_xe_cap_nhat_luc;
        v_vi_tri_ten := 'Xe ' || COALESCE(v_chuyen.bien_so_xe, 'đang vận chuyển');
        v_vi_tri_dia_chi := v_chuyen.kho_di_dia_chi;
        v_diem_den_ten := v_chuyen.kho_den_ten;
        v_diem_den_dia_chi := v_chuyen.kho_den_dia_chi;
    ELSIF v_don.kho_hien_tai_id IS NOT NULL THEN
        v_che_do := 'KHO';
        v_vi_tri_ten := v_kho.ten_kho;
        v_vi_tri_dia_chi := v_kho.dia_chi;
        v_diem_den_ten := CASE WHEN v_don.kho_hien_tai_id = v_don.kho_dich_id
                              THEN 'Địa chỉ người nhận' ELSE 'Kho tiếp theo' END;
        v_diem_den_dia_chi := CASE WHEN v_don.kho_hien_tai_id = v_don.kho_dich_id
                                  THEN v_don.nguoi_nhan_dia_chi ELSE NULL END;
    ELSE
        v_che_do := 'SHIPPER';
        v_vi_do := v_nhan_vien.vi_do;
        v_kinh_do := v_nhan_vien.kinh_do;
        v_cap_nhat := v_nhan_vien.thoi_gian_cap_nhat;
        v_vi_tri_ten := v_nhan_vien.ho_ten;
        IF v_don.trang_thai = 'CHO_LAY_HANG' THEN
            v_diem_den_dia_chi := v_don.nguoi_gui_dia_chi;
            v_diem_den_vi_do := v_don.nguoi_gui_vi_do;
            v_diem_den_kinh_do := v_don.nguoi_gui_kinh_do;
            v_diem_den_ten := 'Điểm lấy hàng';
        ELSIF v_don.trang_thai = 'DA_LAY_HANG' THEN
            SELECT ten_kho, dia_chi INTO v_diem_den_ten, v_diem_den_dia_chi
            FROM public.kho_hang WHERE id = v_don.kho_gui_id;
        ELSE
            v_diem_den_dia_chi := v_don.nguoi_nhan_dia_chi;
            v_diem_den_vi_do := v_don.nguoi_nhan_vi_do;
            v_diem_den_kinh_do := v_don.nguoi_nhan_kinh_do;
            v_diem_den_ten := 'Điểm giao hàng';
        END IF;
    END IF;

    RETURN jsonb_strip_nulls(jsonb_build_object(
        'don_hang_id', v_don.id, 'ma_van_don', v_don.ma_van_don,
        'trang_thai', v_don.trang_thai, 'tracking_mode', v_che_do,
        'ngay_tao', v_don.ngay_tao,
        'nguoi_gui_dia_chi', v_don.nguoi_gui_dia_chi,
        'nguoi_nhan_dia_chi', v_don.nguoi_nhan_dia_chi,
        'nguoi_gui_vi_do', v_don.nguoi_gui_vi_do,
        'nguoi_gui_kinh_do', v_don.nguoi_gui_kinh_do,
        'nguoi_nhan_vi_do', v_don.nguoi_nhan_vi_do,
        'nguoi_nhan_kinh_do', v_don.nguoi_nhan_kinh_do,
        'vi_tri_ten', v_vi_tri_ten, 'vi_tri_dia_chi', v_vi_tri_dia_chi,
        'vi_tri_vi_do', v_vi_do, 'vi_tri_kinh_do', v_kinh_do,
        'vi_tri_cap_nhat_luc', v_cap_nhat,
        'diem_den_ten', v_diem_den_ten, 'diem_den_dia_chi', v_diem_den_dia_chi,
        'diem_den_vi_do', v_diem_den_vi_do, 'diem_den_kinh_do', v_diem_den_kinh_do,
        'shipper_ten', CASE WHEN v_nhan_vien.vai_tro IN ('SHIPPER','NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG') THEN v_nhan_vien.ho_ten END,
        'shipper_sdt', CASE WHEN v_nhan_vien.vai_tro IN ('SHIPPER','NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG') THEN v_nhan_vien.so_dien_thoai END,
        'shipper_vi_do', CASE WHEN v_che_do = 'SHIPPER' THEN v_vi_do END,
        'shipper_kinh_do', CASE WHEN v_che_do = 'SHIPPER' THEN v_kinh_do END,
        'chuyen_xe_id', v_chuyen.id, 'ma_chuyen', v_chuyen.ma_chuyen,
        'chuyen_trang_thai', v_chuyen.chuyen_trang_thai,
        'bien_so_xe', v_chuyen.bien_so_xe, 'tai_xe_ten', v_chuyen.tai_xe_ten,
        'kho_di_ten', v_chuyen.kho_di_ten, 'kho_di_dia_chi', v_chuyen.kho_di_dia_chi,
        'kho_den_ten', v_chuyen.kho_den_ten, 'kho_den_dia_chi', v_chuyen.kho_den_dia_chi,
        'lich_su', v_lich_su, 'cac_chang', v_cac_chang
    ));
END;
$$;

REVOKE ALL ON FUNCTION public.cap_nhat_vi_tri_tai_xe_van_chuyen(
    DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cap_nhat_vi_tri_tai_xe_van_chuyen(
    DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;
REVOKE ALL ON FUNCTION public.theo_doi_don_hang_khach_hang(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.theo_doi_don_hang_khach_hang(BIGINT) TO authenticated;
NOTIFY pgrst, 'reload schema';
