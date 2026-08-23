-- ============================================================
-- DUYET NAP VI: CONG TIEN DUNG MOT LAN
-- Chay file nay trong Supabase SQL Editor. Khong xoa du lieu.
-- ============================================================

CREATE OR REPLACE FUNCTION public.xu_ly_nap_vi_khi_duyet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_so_du_moi NUMERIC;
BEGIN
    -- Chi xu ly khi mot yeu cau NAP_TIEN thuc su chuyen sang DA_DUYET.
    IF NEW.loai <> 'NAP_TIEN'
       OR NEW.trang_thai <> 'DA_DUYET'
       OR OLD.trang_thai = 'DA_DUYET' THEN
        RETURN NEW;
    END IF;

    -- Khoa dong vi va cong tien. Unique index cua giao_dich_vi bao ve
    -- yeu_cau nay khoi bi ghi nhan nhieu lan.
    UPDATE public.vi
    SET so_du = so_du + NEW.so_tien,
        ngay_cap_nhat = NOW()
    WHERE id = NEW.vi_id
    RETURNING so_du INTO v_so_du_moi;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy ví của yêu cầu nạp %', NEW.id;
    END IF;

    INSERT INTO public.giao_dich_vi(
        vi_id,
        yeu_cau_nap_rut_id,
        loai,
        so_tien,
        so_du_sau,
        noi_dung
    ) VALUES (
        NEW.vi_id,
        NEW.id,
        'NAP_TIEN',
        NEW.so_tien,
        v_so_du_moi,
        'Nạp tiền vào ví - yêu cầu #' || NEW.id
    );

    NEW.ngay_xu_ly := COALESCE(NEW.ngay_xu_ly, NOW());
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cong_tien_khi_duyet_nap_vi
ON public.yeu_cau_nap_rut_vi;

CREATE TRIGGER trg_cong_tien_khi_duyet_nap_vi
BEFORE UPDATE OF trang_thai ON public.yeu_cau_nap_rut_vi
FOR EACH ROW
EXECUTE FUNCTION public.xu_ly_nap_vi_khi_duyet();

-- RPC duyet chi doi trang thai. Trigger o tren chiu trach nhiem cong vi,
-- nen duyet tu ung dung hay Table Editor deu co cung mot nghiep vu.
CREATE OR REPLACE FUNCTION public.duyet_yeu_cau_nap_vi(p_yeu_cau_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trang_thai TEXT;
BEGIN
    SELECT yc.trang_thai
    INTO v_trang_thai
    FROM public.yeu_cau_nap_rut_vi yc
    WHERE yc.id = p_yeu_cau_id
      AND yc.loai = 'NAP_TIEN'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy yêu cầu nạp ví';
    END IF;

    IF v_trang_thai = 'DA_DUYET' THEN
        RETURN;
    END IF;

    IF v_trang_thai <> 'CHO_DUYET' THEN
        RAISE EXCEPTION 'Yêu cầu nạp không còn chờ duyệt';
    END IF;

    UPDATE public.yeu_cau_nap_rut_vi
    SET trang_thai = 'DA_DUYET',
        ngay_xu_ly = NOW()
    WHERE id = p_yeu_cau_id;
END;
$$;

REVOKE ALL ON FUNCTION public.duyet_yeu_cau_nap_vi(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.duyet_yeu_cau_nap_vi(BIGINT) TO service_role;

-- Dung cho MOT dong ma ban da sua tay thanh DA_DUYET truoc khi cai trigger.
-- Vi du: SELECT public.sua_yeu_cau_nap_da_duyet(12);
CREATE OR REPLACE FUNCTION public.sua_yeu_cau_nap_da_duyet(p_yeu_cau_id BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_yeu_cau public.yeu_cau_nap_rut_vi%ROWTYPE;
    v_so_du_moi NUMERIC;
BEGIN
    SELECT * INTO v_yeu_cau
    FROM public.yeu_cau_nap_rut_vi
    WHERE id = p_yeu_cau_id
      AND loai = 'NAP_TIEN'
    FOR UPDATE;

    IF NOT FOUND OR v_yeu_cau.trang_thai <> 'DA_DUYET' THEN
        RAISE EXCEPTION 'Yêu cầu nạp chưa ở trạng thái DA_DUYET';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.giao_dich_vi gd
        WHERE gd.yeu_cau_nap_rut_id = v_yeu_cau.id
          AND gd.loai = 'NAP_TIEN'
    ) THEN
        SELECT so_du INTO v_so_du_moi FROM public.vi WHERE id = v_yeu_cau.vi_id;
        RETURN v_so_du_moi;
    END IF;

    UPDATE public.vi
    SET so_du = so_du + v_yeu_cau.so_tien,
        ngay_cap_nhat = NOW()
    WHERE id = v_yeu_cau.vi_id
    RETURNING so_du INTO v_so_du_moi;

    INSERT INTO public.giao_dich_vi(
        vi_id, yeu_cau_nap_rut_id, loai, so_tien, so_du_sau, noi_dung
    ) VALUES (
        v_yeu_cau.vi_id, v_yeu_cau.id, 'NAP_TIEN', v_yeu_cau.so_tien,
        v_so_du_moi, 'Cộng bù yêu cầu nạp đã duyệt #' || v_yeu_cau.id
    );

    RETURN v_so_du_moi;
END;
$$;

REVOKE ALL ON FUNCTION public.sua_yeu_cau_nap_da_duyet(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sua_yeu_cau_nap_da_duyet(BIGINT) TO service_role;

NOTIFY pgrst, 'reload schema';
