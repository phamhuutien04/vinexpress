-- Hiển thị đúng kiện đang đến và đã đến kho trung chuyển.
-- Chạy an toàn nhiều lần trong Supabase SQL Editor, không xóa dữ liệu.

CREATE OR REPLACE FUNCTION public.quan_ly_kho_tong_quan_theo_kho(p_kho_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path=public
AS $$
DECLARE
  v_kho public.kho_hang%ROWTYPE;
  v_quan_ly_ten TEXT;
  v_tinh_thanh VARCHAR;
  v_phuong_xa VARCHAR;
  v_don_tai_kho BIGINT;
  v_don_cho_xu_ly BIGINT;
  v_dang_van_chuyen BIGINT;
  v_da_giao BIGINT;
BEGIN
  IF NOT public.quan_ly_kho_duoc_quan_ly(p_kho_id) THEN
    RAISE EXCEPTION 'Kho không thuộc phạm vi quản lý';
  END IF;

  SELECT * INTO v_kho FROM public.kho_hang WHERE id=p_kho_id;
  SELECT nv.ho_ten INTO v_quan_ly_ten
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid();
  SELECT kv.tinh_thanh,kv.phuong_xa INTO v_tinh_thanh,v_phuong_xa
  FROM public.khu_vuc kv WHERE kv.id=v_kho.khu_vuc_id;

  SELECT COUNT(*) INTO v_don_tai_kho
  FROM public.don_hang dh
  WHERE dh.kho_hien_tai_id=v_kho.id;

  -- Gồm kiện đã nằm tại kho và kiện trên chuyến đã được tài xế xác nhận tới
  -- nhưng nhân viên kho chưa quét nhập kho.
  SELECT COUNT(*) INTO v_don_cho_xu_ly
  FROM (
    SELECT dh.id AS don_hang_id
    FROM public.don_hang dh
    WHERE (dh.kho_gui_id=v_kho.id OR dh.kho_dich_id=v_kho.id OR dh.kho_hien_tai_id=v_kho.id)
      AND dh.trang_thai IN ('DA_LAY_HANG','DEN_KHO_TRUNG_CHUYEN','DEN_KHO_DICH')
    UNION
    SELECT ct.don_hang_id
    FROM public.chi_tiet_chuyen_xe ct
    JOIN public.chuyen_xe cx ON cx.id=ct.chuyen_xe_id
    JOIN public.chuyen_xe_chang c ON c.chuyen_xe_id=cx.id
    JOIN public.don_hang dh ON dh.id=ct.don_hang_id
    WHERE c.kho_den_id=v_kho.id
      AND cx.trang_thai IN ('DA_DEN','DA_HOAN_THANH')
      AND (ct.trang_thai<>'DA_DO_HANG' OR dh.kho_hien_tai_id IS DISTINCT FROM v_kho.id)
  ) cho_xu_ly;

  -- Tính theo kho đến của chuyến để kho trung chuyển vẫn thấy kiện đang tới.
  SELECT COUNT(*) INTO v_dang_van_chuyen
  FROM (
    SELECT dh.id AS don_hang_id
    FROM public.don_hang dh
    WHERE (dh.kho_gui_id=v_kho.id OR dh.kho_dich_id=v_kho.id)
      AND dh.trang_thai='DANG_VAN_CHUYEN'
    UNION
    SELECT ct.don_hang_id
    FROM public.chi_tiet_chuyen_xe ct
    JOIN public.chuyen_xe cx ON cx.id=ct.chuyen_xe_id
    JOIN public.chuyen_xe_chang c ON c.chuyen_xe_id=cx.id
    WHERE c.kho_den_id=v_kho.id
      AND cx.trang_thai='DANG_DI'
      AND ct.trang_thai='DANG_VAN_CHUYEN'
  ) dang_di;

  SELECT COUNT(*) INTO v_da_giao
  FROM public.don_hang dh
  WHERE (dh.kho_gui_id=v_kho.id OR dh.kho_dich_id=v_kho.id)
    AND dh.trang_thai='DA_GIAO_HANG';

  RETURN jsonb_build_object(
    'quan_ly_ten',v_quan_ly_ten,
    'kho_id',v_kho.id,
    'ma_kho',v_kho.ma_kho,
    'ten_kho',v_kho.ten_kho,
    'dia_chi',v_kho.dia_chi,
    'cap_kho',v_kho.cap_kho,
    'tinh_thanh',v_tinh_thanh,
    'phuong_xa',v_phuong_xa,
    'don_tai_kho',v_don_tai_kho,
    'don_cho_xu_ly',v_don_cho_xu_ly,
    'dang_van_chuyen',v_dang_van_chuyen,
    'da_giao',v_da_giao
  );
END;
$$;

REVOKE ALL ON FUNCTION public.quan_ly_kho_tong_quan_theo_kho(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quan_ly_kho_tong_quan_theo_kho(BIGINT) TO authenticated;
NOTIFY pgrst,'reload schema';
