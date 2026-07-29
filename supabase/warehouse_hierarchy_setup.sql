-- ============================================================
-- PHÂN CẤP KHO
-- Cấp 1: kho trung tâm tỉnh/thành, được phép vận chuyển liên tỉnh.
-- Cấp 2: kho vệ tinh, chỉ trung chuyển với kho cấp 1 cùng tỉnh/thành.
-- Chạy file này trước customer_orders_setup.sql.
-- ============================================================

BEGIN;

ALTER TABLE public.kho_hang
    ADD COLUMN IF NOT EXISTS cap_kho SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS kho_trung_tam_id BIGINT;

ALTER TABLE public.kho_hang
    DROP CONSTRAINT IF EXISTS chk_kho_hang_cap_kho;

ALTER TABLE public.kho_hang
    ADD CONSTRAINT chk_kho_hang_cap_kho CHECK (
        (cap_kho = 1 AND kho_trung_tam_id IS NULL)
        OR (cap_kho = 2 AND kho_trung_tam_id IS NOT NULL)
    );

ALTER TABLE public.kho_hang
    DROP CONSTRAINT IF EXISTS fk_kho_hang_kho_trung_tam;

ALTER TABLE public.kho_hang
    ADD CONSTRAINT fk_kho_hang_kho_trung_tam
    FOREIGN KEY (kho_trung_tam_id)
    REFERENCES public.kho_hang(id);

-- Kho mẫu cấp 1: trung tâm của từng tỉnh/thành.
UPDATE public.kho_hang
SET cap_kho = 1,
    kho_trung_tam_id = NULL
WHERE ma_kho IN ('HCM-Q1', 'HN-HK', 'DNG-HC', 'CT-NK');

-- Kho mẫu cấp 2 luôn chuyển về kho trung tâm cùng tỉnh/thành.
UPDATE public.kho_hang AS ve_tinh
SET cap_kho = 2,
    kho_trung_tam_id = trung_tam.id
FROM public.kho_hang AS trung_tam
WHERE (ve_tinh.ma_kho, trung_tam.ma_kho) IN (
    ('HCM-AP', 'HCM-Q1'),
    ('HN-TL', 'HN-HK')
);

-- Bảo vệ cấu trúc: kho cấp 2 phải trỏ tới kho cấp 1 thuộc cùng tỉnh/thành.
CREATE OR REPLACE FUNCTION public.kiem_tra_cay_kho()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_cap_trung_tam SMALLINT;
    v_tinh_kho TEXT;
    v_tinh_trung_tam TEXT;
BEGIN
    IF NEW.cap_kho = 1 THEN
        NEW.kho_trung_tam_id := NULL;
        RETURN NEW;
    END IF;

    SELECT kh.cap_kho, kv.tinh_thanh
    INTO v_cap_trung_tam, v_tinh_trung_tam
    FROM public.kho_hang AS kh
    JOIN public.khu_vuc AS kv ON kv.id = kh.khu_vuc_id
    WHERE kh.id = NEW.kho_trung_tam_id;

    SELECT tinh_thanh
    INTO v_tinh_kho
    FROM public.khu_vuc
    WHERE id = NEW.khu_vuc_id;

    IF NEW.cap_kho <> 2
       OR v_cap_trung_tam <> 1
       OR v_tinh_kho IS DISTINCT FROM v_tinh_trung_tam THEN
        RAISE EXCEPTION
            'Kho cấp 2 phải liên kết với một kho cấp 1 cùng tỉnh/thành';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kiem_tra_cay_kho ON public.kho_hang;
CREATE TRIGGER trg_kiem_tra_cay_kho
BEFORE INSERT OR UPDATE OF cap_kho, kho_trung_tam_id, khu_vuc_id
ON public.kho_hang
FOR EACH ROW
EXECUTE FUNCTION public.kiem_tra_cay_kho();

COMMIT;

SELECT
    kh.ma_kho,
    kh.ten_kho,
    kh.cap_kho,
    trung_tam.ma_kho AS ma_kho_trung_tam
FROM public.kho_hang AS kh
LEFT JOIN public.kho_hang AS trung_tam ON trung_tam.id = kh.kho_trung_tam_id
ORDER BY kh.ma_kho;
