const deno = (globalThis as typeof globalThis & {
  Deno: { serve: (handler: (request: Request) => Response | Promise<Response>) => void; env: { get: (name: string) => string | undefined } }
}).Deno

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
})

deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Chỉ hỗ trợ POST' }, 405)
  const supabaseUrl = deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const clientId = deno.env.get('PAYOS_CLIENT_ID') ?? ''
  const apiKey = deno.env.get('PAYOS_API_KEY') ?? ''
  const authorization = request.headers.get('Authorization') ?? ''
  try {
    if (![supabaseUrl, anonKey, clientId, apiKey].every(Boolean)) throw new Error('PayOS chưa được cấu hình đủ Secrets')
    if (!authorization.startsWith('Bearer ')) throw new Error('Thiếu phiên đăng nhập')
    const body = await request.json()
    const orderCode = Number(body.order_code)
    if (!Number.isInteger(orderCode) || orderCode <= 0) throw new Error('Mã giao dịch không hợp lệ')

    // RPC vừa kiểm tra giao dịch thuộc người dùng hiện tại, vừa ngăn hủy link của người khác.
    const statusResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/trang_thai_giao_dich_payos`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_ma_don_payos: orderCode }),
    })
    const statusRows = await statusResponse.json()
    if (!statusResponse.ok || !Array.isArray(statusRows) || statusRows.length === 0) throw new Error('Không tìm thấy giao dịch PayOS của bạn')
    if (statusRows[0].trang_thai === 'DA_THANH_TOAN') throw new Error('Giao dịch đã thanh toán, không thể hủy')

    const payosResponse = await fetch(`https://api-merchant.payos.vn/v2/payment-requests/${orderCode}/cancel`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-client-id': clientId, 'x-api-key': apiKey },
      body: JSON.stringify({ cancellationReason: 'Khách hàng chọn để sau' }),
    })
    const payosData = await payosResponse.json()
    if (!payosResponse.ok || payosData?.code !== '00') throw new Error(payosData?.desc ?? 'PayOS không thể hủy giao dịch')

    const cancelResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/huy_giao_dich_payos_nap_vi`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_ma_don_payos: orderCode }),
    })
    // RPC trả về VOID thường có body rỗng; không được parse JSON vô điều kiện.
    const cancelText = await cancelResponse.text()
    const cancelData = cancelText ? JSON.parse(cancelText) : null
    if (!cancelResponse.ok) throw new Error(cancelData?.message ?? 'Không lưu được trạng thái hủy')
    return json({ ok: true })
  } catch (error) {
    console.error('payos-cancel-topup:', error)
    return json({ error: error instanceof Error ? error.message : String(error) }, 400)
  }
})
