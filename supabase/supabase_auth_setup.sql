-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor.
-- Giữ database ban đầu và bổ sung auth_user_id để liên kết Supabase Auth.

ALTER TABLE public.khach_hang
    ADD COLUMN IF NOT EXISTS auth_user_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_khach_hang_auth_user
    ON public.khach_hang(auth_user_id)
    WHERE auth_user_id IS NOT NULL;

ALTER TABLE public.khach_hang
    DROP CONSTRAINT IF EXISTS fk_khach_hang_auth_user;

ALTER TABLE public.khach_hang
    ADD CONSTRAINT fk_khach_hang_auth_user
    FOREIGN KEY (auth_user_id)
    REFERENCES auth.users(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE;

-- Mật khẩu thật do Supabase Auth quản lý. Giá trị dưới đây chỉ để đáp ứng
-- cột mat_khau NOT NULL của database ban đầu.
UPDATE public.khach_hang
SET mat_khau = 'SUPABASE_AUTH'
WHERE mat_khau IS NULL;

ALTER TABLE public.khach_hang
    ALTER COLUMN mat_khau SET NOT NULL;

CREATE OR REPLACE FUNCTION public.tao_ho_so_khach_hang()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.khach_hang (
        auth_user_id,
        ho_ten,
        so_dien_thoai,
        email,
        mat_khau,
        dia_chi,
        trang_thai
    )
    VALUES (
        NEW.id,
        COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data->>'ho_ten'), ''), 'Khách hàng'),
        NEW.raw_user_meta_data->>'so_dien_thoai',
        NEW.email,
        'SUPABASE_AUTH',
        NULLIF(BTRIM(NEW.raw_user_meta_data->>'dia_chi'), ''),
        'HOAT_DONG'
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tao_ho_so_khach_hang ON auth.users;

CREATE TRIGGER trg_tao_ho_so_khach_hang
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.tao_ho_so_khach_hang();

ALTER TABLE public.khach_hang ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Khach hang xem ho so cua minh"
    ON public.khach_hang;
CREATE POLICY "Khach hang xem ho so cua minh"
    ON public.khach_hang
    FOR SELECT
    TO authenticated
    USING (auth.uid() = auth_user_id);

DROP POLICY IF EXISTS "Khach hang cap nhat ho so cua minh"
    ON public.khach_hang;
CREATE POLICY "Khach hang cap nhat ho so cua minh"
    ON public.khach_hang
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = auth_user_id)
    WITH CHECK (auth.uid() = auth_user_id);

GRANT SELECT, UPDATE ON TABLE public.khach_hang TO authenticated;
REVOKE ALL ON TABLE public.khach_hang FROM anon;
