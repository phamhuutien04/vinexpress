-- Trả về toàn bộ chặng kho để tài xế xem đúng lộ trình vận chuyển.
-- Chạy an toàn nhiều lần trong Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.chuyen_xe_cua_tai_xe_co_chang()
RETURNS TABLE (
  id BIGINT,
  ma_chuyen VARCHAR,
  trang_thai VARCHAR,
  ngay_khoi_hanh TIMESTAMPTZ,
  ngay_du_kien TIMESTAMPTZ,
  ngay_den_thuc_te TIMESTAMPTZ,
  bien_so_xe VARCHAR,
  tai_trong NUMERIC,
  kho_di_ten VARCHAR,
  kho_den_ten VARCHAR,
  so_don_hang BIGINT,
  chang_duong JSONB,
  da_niem_phong BOOLEAN,
  ma_niem_phong VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path=public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.nhan_vien nv
    WHERE nv.auth_user_id=auth.uid()
      AND nv.vai_tro='VAN_CHUYEN'
      AND nv.trang_thai_duyet='DA_DUYET'
      AND nv.trang_thai='HOAT_DONG'
  ) THEN
    RAISE EXCEPTION 'Không có quyền xem chuyến xe';
  END IF;

  RETURN QUERY
  SELECT cx.id,cx.ma_chuyen::VARCHAR,cx.trang_thai::VARCHAR,
    cx.ngay_khoi_hanh,cx.ngay_du_kien,cx.ngay_den_thuc_te,
    x.bien_so_xe::VARCHAR,x.tai_trong,
    kd.ten_kho::VARCHAR,kden.ten_kho::VARCHAR,
    (SELECT COUNT(*) FROM public.chi_tiet_chuyen_xe ct
      WHERE ct.chuyen_xe_id=cx.id)::BIGINT,
    COALESCE(tuyen.chang_duong,'[]'::JSONB),
    (niem_phong.id IS NOT NULL),
    niem_phong.ma_niem_phong::VARCHAR
  FROM public.chuyen_xe cx
  JOIN public.xe x ON x.id=cx.xe_id
  JOIN public.nhan_vien nv ON nv.id=x.tai_xe_id
  LEFT JOIN LATERAL (
    SELECT c.kho_di_id
    FROM public.chuyen_xe_chang c
    WHERE c.chuyen_xe_id=cx.id
    ORDER BY c.thu_tu_chuyen
    LIMIT 1
  ) dau ON TRUE
  LEFT JOIN LATERAL (
    SELECT c.kho_den_id
    FROM public.chuyen_xe_chang c
    WHERE c.chuyen_xe_id=cx.id
    ORDER BY c.thu_tu_chuyen DESC
    LIMIT 1
  ) cuoi ON TRUE
  LEFT JOIN public.kho_hang kd ON kd.id=dau.kho_di_id
  LEFT JOIN public.kho_hang kden ON kden.id=cuoi.kho_den_id
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id',c.id,
        'thu_tu_chuyen',c.thu_tu_chuyen,
        'trang_thai',c.trang_thai,
        'ngay_khoi_hanh',c.ngay_khoi_hanh,
        'ngay_den_du_kien',c.ngay_den_du_kien,
        'ngay_den_thuc_te',c.ngay_den_thuc_te,
        'kho_di_id',kdi.id,
        'kho_di_ma',kdi.ma_kho,
        'kho_di_ten',kdi.ten_kho,
        'kho_di_dia_chi',kdi.dia_chi,
        'kho_di_so_dien_thoai',kdi.so_dien_thoai,
        'kho_den_id',kde.id,
        'kho_den_ma',kde.ma_kho,
        'kho_den_ten',kde.ten_kho,
        'kho_den_dia_chi',kde.dia_chi,
        'kho_den_so_dien_thoai',kde.so_dien_thoai
      ) ORDER BY c.thu_tu_chuyen
    ) AS chang_duong
    FROM public.chuyen_xe_chang c
    JOIN public.kho_hang kdi ON kdi.id=c.kho_di_id
    JOIN public.kho_hang kde ON kde.id=c.kho_den_id
    WHERE c.chuyen_xe_id=cx.id
  ) tuyen ON TRUE
  LEFT JOIN LATERAL (
    SELECT np.id,np.ma_niem_phong
    FROM public.niem_phong_xe np
    WHERE np.chuyen_xe_id=cx.id
      AND np.trang_thai='DA_NIEM_PHONG'
    ORDER BY np.thoi_gian_niem_phong DESC
    LIMIT 1
  ) niem_phong ON TRUE
  WHERE nv.auth_user_id=auth.uid()
  ORDER BY CASE cx.trang_thai
    WHEN 'DANG_DI' THEN 1
    WHEN 'DANG_XEP_HANG' THEN 2
    WHEN 'CHO_KHOI_HANH' THEN 3
    WHEN 'DA_DEN' THEN 4
    ELSE 5
  END,cx.ngay_tao DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.chuyen_xe_cua_tai_xe_co_chang() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chuyen_xe_cua_tai_xe_co_chang() TO authenticated;
NOTIFY pgrst,'reload schema';
