-- VINEXPRESS - Bật Realtime cho số dư và sao kê ví.
-- An toàn khi chạy lại, không xóa dữ liệu.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'vi'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.vi;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'giao_dich_vi'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.giao_dich_vi;
  END IF;
END;
$$;

ALTER TABLE public.vi REPLICA IDENTITY FULL;
ALTER TABLE public.giao_dich_vi REPLICA IDENTITY FULL;
