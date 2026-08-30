-- Nhân viên kho chỉ thấy chuyến sau khi nhập đúng ID xe hoặc biển số xe.
-- Có thể chạy an toàn nhiều lần trong Supabase SQL Editor.

-- Khóa trùng mã ở cấp database, kể cả khác chữ hoa/thường hoặc khoảng trắng.
-- Unique index cũng xử lý an toàn trường hợp hai nhân viên lưu đồng thời.
CREATE UNIQUE INDEX IF NOT EXISTS uq_niem_phong_ma_chuan
ON public.niem_phong_xe ((UPPER(BTRIM(ma_niem_phong))));

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
      CASE WHEN c.kho_di_id=v_kho_id THEN 'XEP_LEN_XE' ELSE 'NHAP_KHO' END AS thao_tac,
      EXISTS(
        SELECT 1 FROM public.niem_phong_xe np
        WHERE np.chuyen_xe_id=cx.id AND np.trang_thai='DA_NIEM_PHONG'
      ) AS da_niem_phong,
      (SELECT np.ma_niem_phong FROM public.niem_phong_xe np
        WHERE np.chuyen_xe_id=cx.id AND np.trang_thai='DA_NIEM_PHONG'
        ORDER BY np.thoi_gian_niem_phong DESC LIMIT 1) AS ma_niem_phong,
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

CREATE OR REPLACE FUNCTION public.nhan_vien_kho_niem_phong_chuyen(
  p_chuyen_xe_id BIGINT,
  p_ma_niem_phong TEXT
) RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_nhan_vien public.nhan_vien%ROWTYPE;
  v_chuyen public.chuyen_xe%ROWTYPE;
  v_ma TEXT := UPPER(BTRIM(COALESCE(p_ma_niem_phong,'')));
  v_so_kien BIGINT;
BEGIN
  SELECT nv.*
  INTO v_nhan_vien
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='NHAN_VIEN_KHO'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF NOT FOUND OR v_nhan_vien.kho_hang_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên chưa được gán kho';
  END IF;
  IF v_ma='' THEN
    RAISE EXCEPTION 'Hãy nhập mã niêm phong';
  END IF;

  SELECT cx.*
  INTO v_chuyen
  FROM public.chuyen_xe cx
  JOIN public.chuyen_xe_chang c
    ON c.chuyen_xe_id=cx.id AND c.thu_tu_chuyen=1
  WHERE cx.id=p_chuyen_xe_id
    AND c.kho_di_id=v_nhan_vien.kho_hang_id
  FOR UPDATE OF cx;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chuyến xe không xuất phát từ kho của bạn';
  END IF;
  IF v_chuyen.trang_thai NOT IN ('CHO_KHOI_HANH','DANG_XEP_HANG') THEN
    RAISE EXCEPTION 'Trạng thái chuyến không cho phép niêm phong';
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.niem_phong_xe np
    WHERE np.chuyen_xe_id=p_chuyen_xe_id
      AND np.trang_thai='DA_NIEM_PHONG'
  ) THEN
    RAISE EXCEPTION 'Xe đã được niêm phong';
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.niem_phong_xe np
    WHERE UPPER(np.ma_niem_phong)=v_ma
  ) THEN
    RAISE EXCEPTION 'Mã niêm phong đã được sử dụng';
  END IF;

  SELECT COUNT(*)
  INTO v_so_kien
  FROM public.chi_tiet_chuyen_xe ct
  WHERE ct.chuyen_xe_id=p_chuyen_xe_id
    AND ct.trang_thai='DA_XEP_HANG';

  IF v_so_kien=0 THEN
    RAISE EXCEPTION 'Chuyến chưa có kiện hàng để niêm phong';
  END IF;

  BEGIN
    INSERT INTO public.niem_phong_xe(
      chuyen_xe_id,ma_niem_phong,kho_niem_phong_id,
      nguoi_niem_phong_id,trang_thai
    ) VALUES(
      p_chuyen_xe_id,v_ma,v_nhan_vien.kho_hang_id,
      v_nhan_vien.id,'DA_NIEM_PHONG'
    );
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Mã niêm phong đã được sử dụng';
  END;

  RETURN v_ma;
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_kho_tim_chuyen_theo_xe(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_tim_chuyen_theo_xe(TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.nhan_vien_kho_niem_phong_chuyen(BIGINT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_kho_niem_phong_chuyen(BIGINT,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
