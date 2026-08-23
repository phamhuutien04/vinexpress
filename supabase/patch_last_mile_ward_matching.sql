-- VINEXPRESS - Sửa đơn không hiện dù nhân viên và đơn cùng phường/xã.
-- Nguyên nhân: dữ liệu khu_vuc có thể trùng tên nhưng khác id.
-- Bản vá chỉ thay hàm, không xóa dữ liệu.

-- Khi một phường/xã có cả kho cấp 1 và cấp 2, đơn phải vào kho cấp 2 trước.
CREATE OR REPLACE FUNCTION public.tim_kho_theo_dia_chi(
  p_dia_chi TEXT,
  p_kho_bo_qua BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE
  v_kho_id BIGINT;
BEGIN
  SELECT kh.id INTO v_kho_id
  FROM public.kho_hang kh
  JOIN public.khu_vuc kv ON kv.id=kh.khu_vuc_id
  WHERE kh.trang_thai='HOAT_DONG'
    AND public.bo_dau_lower(p_dia_chi)
      LIKE '%' || public.bo_dau_lower(kv.tinh_thanh) || '%'
    AND public.bo_dau_lower(p_dia_chi)
      LIKE '%' || public.bo_dau_lower(kv.phuong_xa) || '%'
    AND (p_kho_bo_qua IS NULL OR kh.id<>p_kho_bo_qua)
  ORDER BY kh.cap_kho DESC, kh.id
  LIMIT 1;

  IF v_kho_id IS NULL THEN
    RAISE EXCEPTION 'Phường/xã trong địa chỉ chưa có kho hoạt động: %',p_dia_chi;
  END IF;
  RETURN v_kho_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2()
RETURNS TABLE(
  id BIGINT, ma_van_don VARCHAR, ma_qr UUID, loai_cong_viec TEXT,
  ten_khach TEXT, so_dien_thoai TEXT, dia_chi TEXT, ten_kho TEXT,
  trang_thai VARCHAR, da_nhan BOOLEAN, ngay_cap_nhat TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
BEGIN
  SELECT nv.* INTO v_nv
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro IN ('NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG')
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản chưa được duyệt hoặc không đúng vai trò';
  END IF;

  RETURN QUERY
  SELECT
    dh.id,
    dh.ma_van_don::VARCHAR,
    dh.ma_qr,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN 'LAY_HANG' ELSE 'GIAO_HANG' END)::TEXT,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nguoi_gui_ten ELSE dh.nguoi_nhan_ten END)::TEXT,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nguoi_gui_sdt ELSE dh.nguoi_nhan_sdt END)::TEXT,
    (CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nguoi_gui_dia_chi ELSE dh.nguoi_nhan_dia_chi END)::TEXT,
    kh.ten_kho::TEXT,
    dh.trang_thai::VARCHAR,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nhan_vien_lay_hang_id=v_nv.id
      ELSE dh.nhan_vien_giao_hang_id=v_nv.id END,
    dh.ngay_cap_nhat
  FROM public.don_hang dh
  JOIN public.kho_hang kh ON kh.id=CASE
    WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN v_nv.kho_hang_id
    ELSE dh.kho_dich_id END
  WHERE (
    v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
    AND dh.trang_thai='CHO_LAY_HANG'
    AND (dh.nhan_vien_lay_hang_id IS NULL OR dh.nhan_vien_lay_hang_id=v_nv.id)
    AND EXISTS (
      SELECT 1
      FROM public.khu_vuc kv_don
      JOIN public.khu_vuc kv_nv ON kv_nv.id=v_nv.khu_vuc_id
      WHERE kv_don.id=dh.khu_vuc_lay_hang_id
        AND public.bo_dau_lower(kv_don.phuong_xa)=public.bo_dau_lower(kv_nv.phuong_xa)
        AND public.bo_dau_lower(kv_don.tinh_thanh)=public.bo_dau_lower(kv_nv.tinh_thanh)
    )
  ) OR (
    v_nv.vai_tro='NHAN_VIEN_GIAO_HANG'
    AND dh.nhan_vien_giao_hang_id=v_nv.id
    AND dh.trang_thai IN ('DEN_KHO_DICH','GIAO_CHO_SHIPPER','DANG_GIAO_HANG')
  )
  ORDER BY dh.ngay_cap_nhat;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_lay_hang_nhan_don(
  p_don_hang_id BIGINT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_nv public.nhan_vien%ROWTYPE;
  v_id BIGINT;
BEGIN
  SELECT nv.* INTO v_nv
  FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='NHAN_VIEN_LAY_HANG'
    AND nv.trang_thai_duyet='DA_DUYET'
    AND nv.trang_thai='HOAT_DONG';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản không phải nhân viên lấy hàng đang hoạt động';
  END IF;

  UPDATE public.don_hang dh
  SET nhan_vien_lay_hang_id=v_nv.id,
      nhan_vien_hien_tai_id=v_nv.id,
      kho_gui_id=v_nv.kho_hang_id,
      kho_trung_tam_gui_id=(
        SELECT CASE
          WHEN kh.cap_kho=1 THEN kh.id
          ELSE kh.kho_trung_tam_id
        END
        FROM public.kho_hang kh
        WHERE kh.id=v_nv.kho_hang_id
      ),
      ngay_cap_nhat=NOW()
  WHERE dh.id=p_don_hang_id
    AND dh.trang_thai='CHO_LAY_HANG'
    AND dh.nhan_vien_lay_hang_id IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.khu_vuc kv_don
      JOIN public.khu_vuc kv_nv ON kv_nv.id=v_nv.khu_vuc_id
      WHERE kv_don.id=dh.khu_vuc_lay_hang_id
        AND public.bo_dau_lower(kv_don.phuong_xa)=public.bo_dau_lower(kv_nv.phuong_xa)
        AND public.bo_dau_lower(kv_don.tinh_thanh)=public.bo_dau_lower(kv_nv.tinh_thanh)
    )
  RETURNING dh.id INTO v_id;

  IF v_id IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.don_hang dh
      WHERE dh.id=p_don_hang_id AND dh.nhan_vien_lay_hang_id=v_nv.id
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Đơn đã được nhân viên khác nhận hoặc không thuộc phường/xã và kho của bạn';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nhan_vien_lay_hang_nhan_don(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nhan_vien_lay_hang_nhan_don(BIGINT) TO authenticated;

NOTIFY pgrst,'reload schema';
