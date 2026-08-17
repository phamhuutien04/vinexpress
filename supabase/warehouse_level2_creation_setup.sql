-- Cho quản lý/nhân viên được gán kho cấp 1 tạo kho cấp 2 trực thuộc.

CREATE OR REPLACE FUNCTION public.thong_tin_quyen_tao_kho_cap_2()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_kho public.kho_hang%ROWTYPE;
BEGIN
    SELECT kh.* INTO v_kho FROM public.nhan_vien nv
    JOIN public.kho_hang kh ON kh.id = nv.kho_hang_id
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'QUAN_LY_KHO'
      AND nv.trang_thai_duyet = 'DA_DUYET' AND nv.trang_thai = 'HOAT_DONG';
    IF NOT FOUND OR v_kho.cap_kho <> 1 THEN RETURN jsonb_build_object('duoc_phep', FALSE); END IF;
    RETURN jsonb_build_object('duoc_phep', TRUE, 'kho_cap_1_id', v_kho.id,
        'ma_kho', v_kho.ma_kho, 'ten_kho', v_kho.ten_kho);
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_tao_kho_cap_2(
    p_ten_kho TEXT, p_dia_chi TEXT, p_tinh_thanh TEXT,
    p_phuong_xa TEXT, p_so_dien_thoai TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_kho_cha public.kho_hang%ROWTYPE;
    v_khu_vuc_id BIGINT;
    v_ma_kho TEXT;
    v_id BIGINT;
BEGIN
    SELECT kh.* INTO v_kho_cha FROM public.nhan_vien nv
    JOIN public.kho_hang kh ON kh.id = nv.kho_hang_id
    WHERE nv.auth_user_id = auth.uid()
      AND nv.vai_tro = 'QUAN_LY_KHO'
      AND nv.trang_thai_duyet = 'DA_DUYET' AND nv.trang_thai = 'HOAT_DONG'
    FOR UPDATE OF kh;
    IF NOT FOUND OR v_kho_cha.cap_kho <> 1 THEN
        RAISE EXCEPTION 'Chỉ quản lý kho cấp 1 mới được tạo kho cấp 2';
    END IF;
    IF NULLIF(BTRIM(p_ten_kho),'') IS NULL OR NULLIF(BTRIM(p_dia_chi),'') IS NULL
       OR NULLIF(BTRIM(p_tinh_thanh),'') IS NULL OR NULLIF(BTRIM(p_phuong_xa),'') IS NULL THEN
        RAISE EXCEPTION 'Thông tin kho chưa đầy đủ';
    END IF;

    SELECT kv.id INTO v_khu_vuc_id FROM public.khu_vuc kv
    WHERE LOWER(BTRIM(kv.tinh_thanh)) = LOWER(BTRIM(p_tinh_thanh))
      AND LOWER(BTRIM(COALESCE(kv.phuong_xa,''))) = LOWER(BTRIM(p_phuong_xa))
    ORDER BY kv.id LIMIT 1;
    IF v_khu_vuc_id IS NULL THEN
        INSERT INTO public.khu_vuc(ten_khu_vuc,tinh_thanh,quan_huyen,phuong_xa)
        VALUES(BTRIM(p_phuong_xa)||', '||BTRIM(p_tinh_thanh),BTRIM(p_tinh_thanh),NULL,BTRIM(p_phuong_xa))
        RETURNING id INTO v_khu_vuc_id;
    END IF;

    LOOP
        v_ma_kho := 'K2-'||UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT,'-','') FROM 1 FOR 8));
        EXIT WHEN NOT EXISTS(SELECT 1 FROM public.kho_hang WHERE ma_kho=v_ma_kho);
    END LOOP;
    INSERT INTO public.kho_hang(ma_kho,ten_kho,dia_chi,khu_vuc_id,so_dien_thoai,
        trang_thai,cap_kho,kho_trung_tam_id)
    VALUES(v_ma_kho,BTRIM(p_ten_kho),BTRIM(p_dia_chi),v_khu_vuc_id,
        NULLIF(BTRIM(p_so_dien_thoai),''),'HOAT_DONG',2,v_kho_cha.id)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- Mọi chặng xe tải ra/vào kho cấp 2 bắt buộc đi qua kho cấp 1 cha.
CREATE OR REPLACE FUNCTION public.kiem_tra_chang_kho_cap_2()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_cap_di SMALLINT; v_cha_di BIGINT;
    v_cap_den SMALLINT; v_cha_den BIGINT;
BEGIN
    SELECT cap_kho,kho_trung_tam_id INTO v_cap_di,v_cha_di
    FROM public.kho_hang WHERE id=NEW.kho_di_id;
    SELECT cap_kho,kho_trung_tam_id INTO v_cap_den,v_cha_den
    FROM public.kho_hang WHERE id=NEW.kho_den_id;
    IF v_cap_di=2 AND NEW.kho_den_id<>v_cha_di THEN
        RAISE EXCEPTION 'Kho cấp 2 chỉ được chuyển hàng lên kho cấp 1 trực thuộc';
    END IF;
    IF v_cap_den=2 AND NEW.kho_di_id<>v_cha_den THEN
        RAISE EXCEPTION 'Hàng vào kho cấp 2 phải đi từ kho cấp 1 trực thuộc';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_kiem_tra_chang_kho_cap_2 ON public.chuyen_xe_chang;
CREATE TRIGGER trg_kiem_tra_chang_kho_cap_2
BEFORE INSERT OR UPDATE OF kho_di_id,kho_den_id ON public.chuyen_xe_chang
FOR EACH ROW EXECUTE FUNCTION public.kiem_tra_chang_kho_cap_2();

REVOKE ALL ON FUNCTION public.thong_tin_quyen_tao_kho_cap_2() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nhan_vien_tao_kho_cap_2(TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.thong_tin_quyen_tao_kho_cap_2() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_tao_kho_cap_2(TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
