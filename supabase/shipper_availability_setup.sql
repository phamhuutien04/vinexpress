-- Chạy sau shipper_nearby_orders_setup.sql. Chỉ áp dụng cho SHIPPER giao chặng ngắn.
ALTER TABLE public.nhan_vien
    ADD COLUMN IF NOT EXISTS san_sang_nhan_don BOOLEAN NOT NULL DEFAULT TRUE;

CREATE OR REPLACE FUNCTION public.trang_thai_nhan_don_shipper()
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_san_sang BOOLEAN;
BEGIN
    SELECT nv.san_sang_nhan_don INTO v_san_sang
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'SHIPPER'
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tài khoản không phải shipper đã được duyệt';
    END IF;
    RETURN v_san_sang;
END;
$$;

CREATE OR REPLACE FUNCTION public.cap_nhat_trang_thai_nhan_don_shipper(
    p_san_sang BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
BEGIN
    IF p_san_sang IS NULL THEN
        RAISE EXCEPTION 'Trạng thái nhận đơn không hợp lệ';
    END IF;

    SELECT nv.id INTO v_nhan_vien_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'SHIPPER'
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET';

    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Tài khoản không phải shipper đã được duyệt';
    END IF;

    -- Đồng bộ với cập nhật GPS/nhận đơn để không bật trực tuyến trở lại do đua lệnh.
    PERFORM pg_advisory_xact_lock(v_nhan_vien_id);
    PERFORM pg_advisory_xact_lock(982451653);

    UPDATE public.nhan_vien
    SET san_sang_nhan_don = p_san_sang
    WHERE id = v_nhan_vien_id;

    UPDATE public.vi_tri_nhan_vien
    SET dang_truc_tuyen = p_san_sang
        AND thoi_gian_cap_nhat >= NOW() - INTERVAL '15 minutes'
    WHERE nhan_vien_id = v_nhan_vien_id;

    IF NOT p_san_sang THEN
        UPDATE public.loi_moi_don_hang_shipper
        SET trang_thai = 'HET_HAN', phan_hoi_luc = NOW()
        WHERE nhan_vien_id = v_nhan_vien_id
          AND trang_thai = 'DANG_MOI';
        PERFORM public.xu_ly_phan_don_shipper();
    END IF;
END;
$$;

-- Cập nhật GPS vẫn được phép khi đang giao đơn, nhưng không được bật lại nhận đơn.
CREATE OR REPLACE FUNCTION public.cap_nhat_vi_tri_shipper(
    p_vi_do DOUBLE PRECISION,
    p_kinh_do DOUBLE PRECISION,
    p_do_chinh_xac_met DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_nhan_vien_id BIGINT;
    v_san_sang BOOLEAN;
BEGIN
    SELECT nv.id INTO v_nhan_vien_id
    FROM public.nhan_vien nv
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'SHIPPER'
      AND nv.trang_thai = 'HOAT_DONG'
      AND nv.trang_thai_duyet = 'DA_DUYET';

    IF v_nhan_vien_id IS NULL THEN
        RAISE EXCEPTION 'Tài khoản không phải shipper đã được duyệt';
    END IF;

    PERFORM pg_advisory_xact_lock(v_nhan_vien_id);
    SELECT nv.san_sang_nhan_don INTO v_san_sang
    FROM public.nhan_vien nv WHERE nv.id = v_nhan_vien_id;

    INSERT INTO public.vi_tri_nhan_vien (
        nhan_vien_id, vi_do, kinh_do, do_chinh_xac_met,
        dang_truc_tuyen, thoi_gian_cap_nhat
    ) VALUES (
        v_nhan_vien_id, p_vi_do, p_kinh_do, p_do_chinh_xac_met,
        v_san_sang, NOW()
    )
    ON CONFLICT (nhan_vien_id) DO UPDATE SET
        vi_do = EXCLUDED.vi_do,
        kinh_do = EXCLUDED.kinh_do,
        do_chinh_xac_met = EXCLUDED.do_chinh_xac_met,
        dang_truc_tuyen = EXCLUDED.dang_truc_tuyen,
        thoi_gian_cap_nhat = NOW();
END;
$$;

REVOKE ALL ON FUNCTION public.trang_thai_nhan_don_shipper() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cap_nhat_trang_thai_nhan_don_shipper(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trang_thai_nhan_don_shipper() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cap_nhat_trang_thai_nhan_don_shipper(BOOLEAN) TO authenticated;
NOTIFY pgrst, 'reload schema';
