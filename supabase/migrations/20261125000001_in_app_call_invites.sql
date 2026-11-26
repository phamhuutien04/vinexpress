CREATE TABLE IF NOT EXISTS public.cuoc_goi_noi_bo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  don_hang_id BIGINT NOT NULL REFERENCES public.don_hang(id) ON DELETE CASCADE,
  nguoi_goi_auth_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nguoi_nhan_auth_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ten_nguoi_goi TEXT NOT NULL,
  trang_thai TEXT NOT NULL DEFAULT 'DANG_GOI'
    CHECK (trang_thai IN ('DANG_GOI', 'DA_NHAN', 'TU_CHOI', 'KET_THUC')),
  het_han_luc TIMESTAMPTZ NOT NULL DEFAULT now() + interval '45 seconds',
  ngay_tao TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cuoc_goi_noi_bo_nguoi_nhan
  ON public.cuoc_goi_noi_bo(nguoi_nhan_auth_id, ngay_tao DESC);

ALTER TABLE public.cuoc_goi_noi_bo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Nguoi tham gia xem cuoc goi cua minh" ON public.cuoc_goi_noi_bo;
CREATE POLICY "Nguoi tham gia xem cuoc goi cua minh"
  ON public.cuoc_goi_noi_bo FOR SELECT TO authenticated
  USING (auth.uid() = nguoi_goi_auth_id OR auth.uid() = nguoi_nhan_auth_id);

ALTER TABLE public.cuoc_goi_noi_bo REPLICA IDENTITY FULL;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.cuoc_goi_noi_bo;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
