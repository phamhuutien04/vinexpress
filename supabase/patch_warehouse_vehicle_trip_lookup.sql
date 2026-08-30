-- Nhân viên kho chỉ thấy chuyến sau khi nhập đúng ID xe hoặc biển số xe.
-- Có thể chạy an toàn nhiều lần trong Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_tim_chuyen_theo_xe(
  p_tu_khoa TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path=public
AS $$
DECLARE
  v_kho_id BIGINT;
  v_xe public.xe%ROWTYPE;
  v_tu_khoa TEXT := BTRIM(COALESCE(p_tu_khoa,''));
  v_bien_so_chuan TEXT;
  v_chuyen_xe JSONB;
BEGIN
  SELECT nv.kho_hang_id
  INTO v_kho_id
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF v_kho_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;
  IF v_tu_khoa='' THEN
    RAISE EXCEPTION 'Hãy nhập ID xe hoặc biển số xe';
  END IF;

  v_bien_so_chuan := regexp_replace(UPPER(v_tu_khoa),'[^A-Z0-9]','','g');

  SELECT x.*
  INTO v_xe
  FROM public.xe x
  LEFT JOIN public.nhan_vien tx ON tx.id=x.tai_xe_id
  WHERE (
      (v_tu_khoa ~ '^[0-9]+$' AND x.id::TEXT=v_tu_khoa)
      OR regexp_replace(UPPER(x.bien_so_xe),'[^A-Z0-9]','','g')=v_bien_so_chuan
    )
    AND (
      tx.kho_hang_id=v_kho_id
      OR EXISTS (
        SELECT 1
        FROM public.chuyen_xe cx
        JOIN public.chuyen_xe_chang c
          ON c.chuyen_xe_id=cx.id AND c.thu_tu_chuyen=1
        WHERE cx.xe_id=x.id
          AND (
            (c.kho_di_id=v_kho_id AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG'))
            OR (c.kho_den_id=v_kho_id AND cx.trang_thai IN ('DANG_DI','DA_DEN'))
          )
      )
    )
  ORDER BY CASE WHEN x.id::TEXT=v_tu_khoa THEN 0 ELSE 1 END
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy xe trong phạm vi kho với ID hoặc biển số đã nhập';
  END IF;

  SELECT COALESCE(
    jsonb_agg(to_jsonb(q)-'ngay_tao' ORDER BY q.ngay_tao DESC),
    '[]'::JSONB
  )
  INTO v_chuyen_xe
  FROM (
    SELECT cx.id,cx.ma_chuyen::VARCHAR,cx.trang_thai::VARCHAR,
      x.bien_so_xe::VARCHAR,tx.ho_ten::VARCHAR AS ten_tai_xe,
      c.kho_di_id,kd.ten_kho::VARCHAR AS ten_kho_di,
      c.kho_den_id,kn.ten_kho::VARCHAR AS ten_kho_den,
      (SELECT COUNT(*) FROM public.chi_tiet_chuyen_xe ct
        WHERE ct.chuyen_xe_id=cx.id)::BIGINT AS so_kien,
      cx.ngay_tao
    FROM public.chuyen_xe cx
    JOIN public.xe x ON x.id=cx.xe_id
    LEFT JOIN public.nhan_vien tx ON tx.id=x.tai_xe_id
    JOIN public.chuyen_xe_chang c
      ON c.chuyen_xe_id=cx.id AND c.thu_tu_chuyen=1
    JOIN public.kho_hang kd ON kd.id=c.kho_di_id
    JOIN public.kho_hang kn ON kn.id=c.kho_den_id
    WHERE cx.xe_id=v_xe.id
      AND (
        (c.kho_di_id=v_kho_id AND cx.trang_thai IN ('CHO_KHOI_HANH','DANG_XEP_HANG'))
        OR (c.kho_den_id=v_kho_id AND cx.trang_thai IN ('DANG_DI','DA_DEN'))
      )
  ) q;

  RETURN jsonb_build_object(
    'xe',jsonb_build_object(
      'id',v_xe.id,
      'bien_so_xe',v_xe.bien_so_xe,
      'trang_thai',v_xe.trang_thai,
      'ten_tai_xe',(SELECT nv.ho_ten FROM public.nhan_vien nv WHERE nv.id=v_xe.tai_xe_id)
    ),
    'chuyen_xe',v_chuyen_xe
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_kho_tim_chuyen_theo_xe(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_tim_chuyen_theo_xe(TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
