const deno = (globalThis as typeof globalThis & {
  Deno: { serve: (handler: (request: Request) => Response | Promise<Response>) => void; env: { get: (name: string) => string | undefined } }
}).Deno

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' },
})

deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Chỉ hỗ trợ POST' }, 405)

  const supabaseUrl = deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const clientId = deno.env.get('PAYOS_CLIENT_ID') ?? ''
  const apiKey = deno.env.get('PAYOS_API_KEY') ?? ''
  const authorization = request.headers.get('Authorization') ?? ''

  try {
    if (![supabaseUrl, anonKey, serviceKey, clientId, apiKey].every(Boolean)) {
      throw new Error('PayOS chưa được cấu hình đủ Secrets trên Supabase')
    }
    if (!authorization.startsWith('Bearer ')) throw new Error('Thiếu phiên đăng nhập')

    const { order_code: rawOrderCode } = await request.json()
    const orderCode = Number(rawOrderCode)
    if (!Number.isInteger(orderCode) || orderCode <= 0) throw new Error('Mã giao dịch không hợp lệ')

    // Kiểm tra giao dịch có thuộc chính người đang gọi hay không trước khi hỏi PayOS.
    const statusResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/trang_thai_giao_dich_payos`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_ma_don_payos: orderCode }),
    })
    const statusRows = await statusResponse.json()
    if (!statusResponse.ok || !Array.isArray(statusRows) || statusRows.length === 0) {
      throw new Error('Không tìm thấy giao dịch PayOS của bạn')
    }
    if (statusRows[0].trang_thai === 'DA_THANH_TOAN') return json({ paid: true })

    // Đây là phương án dự phòng khi webhook bị chậm/lỡ: chỉ PayOS mới là nguồn
    // xác nhận, tuyệt đối không cộng ví dựa vào trạng thái từ ứng dụng.
    const payosResponse = await fetch(`https://api-merchant.payos.vn/v2/payment-requests/${orderCode}`, {
      headers: { 'x-client-id': clientId, 'x-api-key': apiKey },
    })
    const payosResult = await payosResponse.json()
    const payment = payosResult?.data
    if (!payosResponse.ok || payosResult?.code !== '00' || !payment) {
      throw new Error(payosResult?.desc ?? 'Không kiểm tra được trạng thái PayOS')
    }
    if (payment.status !== 'PAID') return json({ paid: false })

    const confirmResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/xac_nhan_giao_dich_payos_nap_vi`, {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_ma_don_payos: orderCode,
        p_payment_link_id: String(payment.paymentLinkId ?? ''),
        p_ma_tham_chieu: String(payment.reference ?? ''),
        p_so_tien: Number(payment.amount),
        p_du_lieu_webhook: { source: 'payos-sync-topup', data: payment },
      }),
    })
    const confirmText = await confirmResponse.text()
    if (!confirmResponse.ok) {
      let message = 'Không thể cập nhật số dư ví'
      try { message = JSON.parse(confirmText)?.message ?? message } catch (_) { /* response rỗng */ }
      throw new Error(message)
    }
    return json({ paid: true })
  } catch (error) {
    console.error('payos-sync-topup:', error)
    return json({ error: error instanceof Error ? error.message : String(error) }, 400)
  }
})
