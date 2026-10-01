-- Báo cáo sự cố chuyến xe: tài xế gửi minh chứng, Admin duyệt hoặc từ chối.

CREATE TABLE IF NOT EXISTS public.su_co_van_chuyen (
  id BIGSERIAL PRIMARY KEY,
  chuyen_xe_id BIGINT NOT NULL REFERENCES public.chuyen_xe(id) ON DELETE CASCADE,
  tai_xe_id BIGINT NOT NULL REFERENCES public.nhan_vien(id),
  loai_su_co VARCHAR(50) NOT NULL,
  mo_ta TEXT NOT NULL CHECK (char_length(trim(mo_ta)) >= 10),
  anh_minh_chung_url TEXT NOT NULL,
  trang_thai VARCHAR(20) NOT NULL DEFAULT 'CHO_DUYET'
    CHECK (trang_thai IN ('CHO_DUYET','DA_DUYET','TU_CHOI')),
  ghi_chu_admin TEXT,
  admin_xu_ly_id BIGINT REFERENCES public.nhan_vien(id),
  ngay_tao TIMESTAMPTZ NOT NULL DEFAULT now(),
  ngay_xu_ly TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_su_co_van_chuyen_chuyen
  ON public.su_co_van_chuyen(chuyen_xe_id, ngay_tao DESC);
CREATE INDEX IF NOT EXISTS idx_su_co_van_chuyen_trang_thai
  ON public.su_co_van_chuyen(trang_thai, ngay_tao DESC);

ALTER TABLE public.su_co_van_chuyen ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.tai_xe_bao_cao_su_co(
  p_chuyen_xe_id BIGINT,
  p_loai_su_co TEXT,
  p_mo_ta TEXT,
  p_anh_minh_chung_url TEXT
) RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_tai_xe_id BIGINT; v_id BIGINT;
BEGIN
  SELECT nv.id INTO v_tai_xe_id
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='VAN_CHUYEN'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF v_tai_xe_id IS NULL THEN RAISE EXCEPTION 'Không xác định được tài xế vận chuyển'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.chuyen_xe cx JOIN public.xe x ON x.id=cx.xe_id
    WHERE cx.id=p_chuyen_xe_id AND x.tai_xe_id=v_tai_xe_id
  ) THEN RAISE EXCEPTION 'Chuyến xe không thuộc tài xế đang đăng nhập'; END IF;
  IF trim(coalesce(p_mo_ta,''))='' OR char_length(trim(p_mo_ta))<10 THEN
    RAISE EXCEPTION 'Mô tả sự cố phải có ít nhất 10 ký tự';
  END IF;
  IF trim(coalesce(p_anh_minh_chung_url,''))='' THEN RAISE EXCEPTION 'Phải có ảnh minh chứng'; END IF;

  INSERT INTO public.su_co_van_chuyen(chuyen_xe_id,tai_xe_id,loai_su_co,mo_ta,anh_minh_chung_url)
  VALUES(p_chuyen_xe_id,v_tai_xe_id,upper(trim(p_loai_su_co)),trim(p_mo_ta),trim(p_anh_minh_chung_url))
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_danh_sach_su_co_van_chuyen()
RETURNS TABLE(
  id BIGINT, chuyen_xe_id BIGINT, ma_chuyen VARCHAR, bien_so_xe VARCHAR,
  tai_xe_ten VARCHAR, loai_su_co VARCHAR, mo_ta TEXT, anh_minh_chung_url TEXT,
  trang_thai VARCHAR, ghi_chu_admin TEXT, ngay_tao TIMESTAMPTZ, ngay_xu_ly TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được xem báo cáo sự cố'; END IF;
  RETURN QUERY
  SELECT sc.id,sc.chuyen_xe_id,cx.ma_chuyen::VARCHAR,x.bien_so_xe::VARCHAR,
    nv.ho_ten::VARCHAR,sc.loai_su_co,sc.mo_ta,sc.anh_minh_chung_url,
    sc.trang_thai,sc.ghi_chu_admin,sc.ngay_tao,sc.ngay_xu_ly
  FROM public.su_co_van_chuyen sc
  JOIN public.chuyen_xe cx ON cx.id=sc.chuyen_xe_id
  JOIN public.xe x ON x.id=cx.xe_id
  JOIN public.nhan_vien nv ON nv.id=sc.tai_xe_id
  ORDER BY CASE WHEN sc.trang_thai='CHO_DUYET' THEN 0 ELSE 1 END, sc.ngay_tao DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.tai_xe_danh_sach_su_co()
RETURNS TABLE(
  id BIGINT, chuyen_xe_id BIGINT, ma_chuyen VARCHAR, bien_so_xe VARCHAR,
  loai_su_co VARCHAR, mo_ta TEXT, anh_minh_chung_url TEXT,
  trang_thai VARCHAR, ghi_chu_admin TEXT, ngay_tao TIMESTAMPTZ, ngay_xu_ly TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_tai_xe_id BIGINT;
BEGIN
  SELECT nv.id INTO v_tai_xe_id FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid() AND nv.vai_tro='VAN_CHUYEN';
  IF v_tai_xe_id IS NULL THEN RAISE EXCEPTION 'Không xác định được tài xế vận chuyển'; END IF;
  RETURN QUERY
  SELECT sc.id,sc.chuyen_xe_id,cx.ma_chuyen::VARCHAR,x.bien_so_xe::VARCHAR,
    sc.loai_su_co,sc.mo_ta,sc.anh_minh_chung_url,sc.trang_thai,
    sc.ghi_chu_admin,sc.ngay_tao,sc.ngay_xu_ly
  FROM public.su_co_van_chuyen sc
  JOIN public.chuyen_xe cx ON cx.id=sc.chuyen_xe_id
  JOIN public.xe x ON x.id=cx.xe_id
  WHERE sc.tai_xe_id=v_tai_xe_id
  ORDER BY sc.ngay_tao DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_xu_ly_su_co_van_chuyen(
  p_su_co_id BIGINT, p_hanh_dong TEXT, p_ghi_chu TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_admin_id BIGINT; v_trang_thai TEXT;
BEGIN
  IF NOT public.la_admin() THEN RAISE EXCEPTION 'Chỉ ADMIN mới được xử lý báo cáo sự cố'; END IF;
  SELECT id INTO v_admin_id FROM public.nhan_vien WHERE auth_user_id=auth.uid();
  v_trang_thai := CASE upper(trim(p_hanh_dong))
    WHEN 'DUYET' THEN 'DA_DUYET' WHEN 'TU_CHOI' THEN 'TU_CHOI' ELSE NULL END;
  IF v_trang_thai IS NULL THEN RAISE EXCEPTION 'Hành động không hợp lệ'; END IF;
  UPDATE public.su_co_van_chuyen SET trang_thai=v_trang_thai,
    ghi_chu_admin=nullif(trim(coalesce(p_ghi_chu,'')),''),
    admin_xu_ly_id=v_admin_id, ngay_xu_ly=now()
  WHERE id=p_su_co_id AND trang_thai='CHO_DUYET';
  IF NOT FOUND THEN RAISE EXCEPTION 'Báo cáo không tồn tại hoặc đã được xử lý'; END IF;
END; $$;

REVOKE ALL ON FUNCTION public.tai_xe_bao_cao_su_co(BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_danh_sach_su_co_van_chuyen() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tai_xe_danh_sach_su_co() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_xu_ly_su_co_van_chuyen(BIGINT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tai_xe_bao_cao_su_co(BIGINT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_danh_sach_su_co_van_chuyen() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tai_xe_danh_sach_su_co() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_xu_ly_su_co_van_chuyen(BIGINT,TEXT,TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
