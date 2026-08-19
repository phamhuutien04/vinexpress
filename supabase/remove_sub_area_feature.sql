-- Go tinh nang khu pho/ap/thon, quay lai phan cong theo phuong/xa.
-- KHONG xoa don hang, khach hang hoac nhan vien.

DROP FUNCTION IF EXISTS public.danh_sach_dia_ban_giao_nhan(BIGINT);
DROP FUNCTION IF EXISTS public.luu_dia_ban_giao_nhan(BIGINT,TEXT);
DROP FUNCTION IF EXISTS public.tim_dia_ban_giao_nhan(TEXT,BIGINT);

ALTER TABLE public.nhan_vien
  DROP COLUMN IF EXISTS dia_ban_giao_nhan_id;

ALTER TABLE public.don_hang
  DROP COLUMN IF EXISTS dia_ban_lay_hang_id,
  DROP COLUMN IF EXISTS dia_ban_giao_hang_id;

DROP TABLE IF EXISTS public.dia_ban_giao_nhan;

CREATE OR REPLACE FUNCTION public.kiem_tra_dia_ban_nhan_vien_chang_cuoi()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$
DECLARE
  v_kho_cap SMALLINT;
  v_kho_tinh_thanh TEXT;
  v_nhan_vien_tinh_thanh TEXT;
BEGIN
  IF NEW.vai_tro NOT IN ('NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG') THEN
    RETURN NEW;
  END IF;
  IF NEW.kho_hang_id IS NULL OR NEW.khu_vuc_id IS NULL THEN
    RAISE EXCEPTION 'Nhân viên lấy/giao hàng phải có kho cấp 2 và phường/xã phụ trách';
  END IF;
  SELECT kh.cap_kho,kv.tinh_thanh
  INTO v_kho_cap,v_kho_tinh_thanh
  FROM public.kho_hang kh
  JOIN public.khu_vuc kv ON kv.id=kh.khu_vuc_id
  WHERE kh.id=NEW.kho_hang_id;
  IF v_kho_cap IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'Nhân viên lấy/giao hàng chỉ được gán vào kho cấp 2';
  END IF;
  SELECT kv.tinh_thanh INTO v_nhan_vien_tinh_thanh
  FROM public.khu_vuc kv WHERE kv.id=NEW.khu_vuc_id;
  IF public.bo_dau_lower(v_kho_tinh_thanh)
     IS DISTINCT FROM public.bo_dau_lower(v_nhan_vien_tinh_thanh) THEN
    RAISE EXCEPTION 'Phường/xã phụ trách phải cùng tỉnh/thành với kho cấp 2';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kiem_tra_dia_ban_nhan_vien_chang_cuoi
ON public.nhan_vien;
CREATE TRIGGER trg_kiem_tra_dia_ban_nhan_vien_chang_cuoi
BEFORE INSERT OR UPDATE OF vai_tro,kho_hang_id,khu_vuc_id
ON public.nhan_vien
FOR EACH ROW EXECUTE FUNCTION public.kiem_tra_dia_ban_nhan_vien_chang_cuoi();

CREATE OR REPLACE FUNCTION public.phan_cong_nhan_vien_chang_cuoi()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.khu_vuc_lay_hang_id IS NULL THEN
    NEW.khu_vuc_lay_hang_id := public.tim_khu_vuc_theo_dia_chi(NEW.nguoi_gui_dia_chi);
  END IF;
  IF NEW.khu_vuc_giao_hang_id IS NULL THEN
    NEW.khu_vuc_giao_hang_id := public.tim_khu_vuc_theo_dia_chi(NEW.nguoi_nhan_dia_chi);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_chang_cuoi_cong_viec_v2()
RETURNS TABLE(id BIGINT,ma_van_don VARCHAR,ma_qr UUID,loai_cong_viec TEXT,
  ten_khach TEXT,so_dien_thoai TEXT,dia_chi TEXT,ten_kho TEXT,
  trang_thai VARCHAR,da_nhan BOOLEAN,ngay_cap_nhat TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE;
BEGIN
  SELECT nv.* INTO v_nv FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro IN ('NHAN_VIEN_LAY_HANG','NHAN_VIEN_GIAO_HANG')
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản chưa được duyệt hoặc không đúng vai trò';
  END IF;
  RETURN QUERY
  SELECT dh.id,dh.ma_van_don::VARCHAR,dh.ma_qr,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN 'LAY_HANG' ELSE 'GIAO_HANG' END,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN dh.nguoi_gui_ten ELSE dh.nguoi_nhan_ten END,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN dh.nguoi_gui_sdt ELSE dh.nguoi_nhan_sdt END,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN dh.nguoi_gui_dia_chi ELSE dh.nguoi_nhan_dia_chi END,
    kh.ten_kho::TEXT,dh.trang_thai::VARCHAR,
    CASE WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
      THEN dh.nhan_vien_lay_hang_id=v_nv.id
      ELSE dh.nhan_vien_giao_hang_id=v_nv.id END,
    dh.ngay_cap_nhat
  FROM public.don_hang dh
  JOIN public.kho_hang kh ON kh.id=CASE
    WHEN v_nv.vai_tro='NHAN_VIEN_LAY_HANG' THEN dh.kho_gui_id
    ELSE dh.kho_dich_id END
  WHERE (v_nv.vai_tro='NHAN_VIEN_LAY_HANG'
         AND dh.kho_gui_id=v_nv.kho_hang_id
         AND dh.khu_vuc_lay_hang_id=v_nv.khu_vuc_id
         AND dh.trang_thai='CHO_LAY_HANG'
         AND (dh.nhan_vien_lay_hang_id IS NULL OR dh.nhan_vien_lay_hang_id=v_nv.id))
     OR (v_nv.vai_tro='NHAN_VIEN_GIAO_HANG'
         AND dh.nhan_vien_giao_hang_id=v_nv.id
         AND dh.trang_thai IN ('DEN_KHO_DICH','GIAO_CHO_SHIPPER','DANG_GIAO_HANG'))
  ORDER BY dh.ngay_cap_nhat;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_lay_hang_nhan_don(p_don_hang_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE; v_id BIGINT;
BEGIN
  SELECT nv.* INTO v_nv FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='NHAN_VIEN_LAY_HANG'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản không phải nhân viên lấy hàng đang hoạt động';
  END IF;
  UPDATE public.don_hang dh
  SET nhan_vien_lay_hang_id=v_nv.id,nhan_vien_hien_tai_id=v_nv.id,
      ngay_cap_nhat=NOW()
  WHERE dh.id=p_don_hang_id AND dh.trang_thai='CHO_LAY_HANG'
    AND dh.kho_gui_id=v_nv.kho_hang_id
    AND dh.khu_vuc_lay_hang_id=v_nv.khu_vuc_id
    AND dh.nhan_vien_lay_hang_id IS NULL
  RETURNING dh.id INTO v_id;
  IF v_id IS NULL THEN
    IF EXISTS(SELECT 1 FROM public.don_hang dh
      WHERE dh.id=p_don_hang_id AND dh.nhan_vien_lay_hang_id=v_nv.id) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Đơn đã được nhân viên khác nhận hoặc không thuộc phường/xã của bạn';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.nhan_vien_giao_hang_quet_kien(p_ma TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_nv public.nhan_vien%ROWTYPE; v_don public.don_hang%ROWTYPE;
BEGIN
  SELECT nv.* INTO v_nv FROM public.nhan_vien nv
  WHERE nv.auth_user_id=auth.uid()
    AND nv.vai_tro='NHAN_VIEN_GIAO_HANG'
    AND nv.trang_thai_duyet='DA_DUYET' AND nv.trang_thai='HOAT_DONG';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tài khoản không phải nhân viên giao hàng đang hoạt động';
  END IF;
  SELECT dh.* INTO v_don FROM public.don_hang dh
  WHERE dh.ma_qr::TEXT=BTRIM(p_ma)
     OR UPPER(dh.ma_van_don)=UPPER(BTRIM(p_ma)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy kiện hàng'; END IF;
  IF v_don.kho_dich_id<>v_nv.kho_hang_id
     OR v_don.khu_vuc_giao_hang_id<>v_nv.khu_vuc_id THEN
    RAISE EXCEPTION 'Kiện hàng không thuộc kho hoặc phường/xã bạn phụ trách';
  END IF;
  IF v_don.trang_thai NOT IN ('DEN_KHO_DICH','GIAO_CHO_SHIPPER') THEN
    RAISE EXCEPTION 'Kiện hàng chưa sẵn sàng để giao';
  END IF;
  IF v_don.nhan_vien_giao_hang_id IS NOT NULL
     AND v_don.nhan_vien_giao_hang_id<>v_nv.id THEN
    RAISE EXCEPTION 'Kiện hàng đã được nhân viên khác quét nhận';
  END IF;
  UPDATE public.don_hang
  SET nhan_vien_giao_hang_id=v_nv.id,nhan_vien_hien_tai_id=v_nv.id,
      trang_thai='GIAO_CHO_SHIPPER',ngay_cap_nhat=NOW()
  WHERE id=v_don.id;
  RETURN v_don.id;
END;
$$;

NOTIFY pgrst,'reload schema';
