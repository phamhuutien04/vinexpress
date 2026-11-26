import { createClient } from "npm:@supabase/supabase-js@2";
// Thư viện này chạy ổn định trên Deno/Supabase Edge Runtime.
import { RtcRole, RtcTokenBuilder } from "npm:agora-access-token@2.0.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) throw new Error("Bạn cần đăng nhập để gọi trong ứng dụng.");

    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const appId = Deno.env.get("AGORA_APP_ID");
    const certificate = Deno.env.get("AGORA_APP_CERTIFICATE");
    if (!appId || !certificate) throw new Error("Dịch vụ gọi chưa được cấu hình.");

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const admin = createClient(url, serviceKey);
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) throw new Error("Phiên đăng nhập đã hết hạn.");

    const { action = "start", orderId, notify = true, callId: requestedCallId } = await req.json();
    if (action === "end") {
      if (typeof requestedCallId !== "string" || !requestedCallId) throw new Error("Cuộc gọi không hợp lệ.");
      const { data: authData, error: authError } = await userClient.auth.getUser();
      if (authError || !authData.user) throw new Error("Phiên đăng nhập đã hết hạn.");
      const { data: call } = await admin
        .from("cuoc_goi_noi_bo")
        .select("id, nguoi_goi_auth_id, nguoi_nhan_auth_id")
        .eq("id", requestedCallId)
        .maybeSingle();
      if (!call || (call.nguoi_goi_auth_id !== authData.user.id && call.nguoi_nhan_auth_id !== authData.user.id)) {
        throw new Error("Bạn không có quyền kết thúc cuộc gọi này.");
      }
      await admin.from("cuoc_goi_noi_bo").update({ trang_thai: "KET_THUC" }).eq("id", requestedCallId);
      return Response.json({ ended: true }, { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const parsedOrderId = Number(orderId);
    if (!Number.isInteger(parsedOrderId) || parsedOrderId <= 0) {
      throw new Error("Đơn hàng không hợp lệ.");
    }

    const { data: order, error: orderError } = await admin
      .from("don_hang")
      .select("id, ma_van_don, khach_hang_id, nhan_vien_hien_tai_id")
      .eq("id", parsedOrderId)
      .maybeSingle();
    if (orderError || !order) throw new Error("Không tìm thấy đơn hàng.");

    const userId = authData.user.id;
    const [{ data: customer }, { data: employee }] = await Promise.all([
      admin.from("khach_hang").select("id, ho_ten").eq("auth_user_id", userId).maybeSingle(),
      admin.from("nhan_vien").select("id, ho_ten").eq("auth_user_id", userId).maybeSingle(),
    ]);

    let uid = 0;
    let callerRole = "";
    let recipientAuthUserId = "";
    if (customer?.id === order.khach_hang_id) {
      uid = 1;
      callerRole = "KHACH_HANG";
      const { data: recipient } = await admin
        .from("nhan_vien")
        .select("auth_user_id")
        .eq("id", order.nhan_vien_hien_tai_id)
        .maybeSingle();
      recipientAuthUserId = recipient?.auth_user_id ?? "";
    } else if (employee?.id === order.nhan_vien_hien_tai_id) {
      uid = 2;
      callerRole = "SHIPPER";
      const { data: recipient } = await admin
        .from("khach_hang")
        .select("auth_user_id")
        .eq("id", order.khach_hang_id)
        .maybeSingle();
      recipientAuthUserId = recipient?.auth_user_id ?? "";
    } else {
      throw new Error("Bạn không có quyền gọi cho đơn hàng này.");
    }

    const channel = `vex-${order.id}`;
    const expiresAt = Math.floor(Date.now() / 1000) + 60 * 30;
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      certificate,
      channel,
      uid,
      RtcRole.PUBLISHER,
      expiresAt,
    );

    let createdCallId: string | null = null;
    if (notify && recipientAuthUserId) {
      const callerName = customer?.ho_ten ?? employee?.ho_ten ?? "VinExpress";
      const { data: call } = await admin.from("cuoc_goi_noi_bo").insert({
        don_hang_id: order.id,
        nguoi_goi_auth_id: userId,
        nguoi_nhan_auth_id: recipientAuthUserId,
        ten_nguoi_goi: callerName,
        het_han_luc: new Date(Date.now() + 30_000).toISOString(),
      }).select("id").single();
      createdCallId = call?.id ?? null;
    }

    return Response.json({
      appId,
      token,
      channel,
      uid,
      expiresAt,
      callerRole,
      orderCode: order.ma_van_don,
      callId: createdCallId,
    }, { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Không thể khởi tạo cuộc gọi." },
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
