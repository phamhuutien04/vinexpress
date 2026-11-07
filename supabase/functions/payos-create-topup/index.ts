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

async function hmacSha256(value: string, secret: string) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  )
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value))
  return Array.from(new Uint8Array(signature)).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Chỉ hỗ trợ POST' }, 405)

  const supabaseUrl = deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const clientId = deno.env.get('PAYOS_CLIENT_ID') ?? ''
  const apiKey = deno.env.get('PAYOS_API_KEY') ?? ''
  const checksumKey = deno.env.get('PAYOS_CHECKSUM_KEY') ?? ''
  const returnUrl = deno.env.get('PAYOS_RETURN_URL') ?? ''
  const cancelUrl = deno.env.get('PAYOS_CANCEL_URL') ?? ''
  const authorization = request.headers.get('Authorization') ?? ''

  try {
    if (![supabaseUrl, anonKey, serviceKey, clientId, apiKey, checksumKey, returnUrl, cancelUrl].every(Boolean)) {
      throw new Error('PayOS chưa được cấu hình đủ Secrets trên Supabase')
    }
    if (!authorization.startsWith('Bearer ')) throw new Error('Thiếu phiên đăng nhập')
    const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: authorization },
    })
    const user = await userResponse.json()
    if (!userResponse.ok || !user?.id) throw new Error('Phiên đăng nhập không hợp lệ')

    const body = await request.json()
    const amount = Math.round(Number(body.amount ?? 0))
    if (!Number.isInteger(amount) || amount < 10000 || amount > 50000000) {
      throw new Error('Số tiền nạp phải từ 10.000đ đến 50.000.000đ')
    }

    const requestResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/tao_yeu_cau_nap_vi`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_so_tien: amount, p_phuong_thuc: 'PAYOS' }),
    })
    const topUpRequestId = await requestResponse.json()
    if (!requestResponse.ok) throw new Error(topUpRequestId.message ?? 'Không tạo được yêu cầu nạp ví')

    const paymentResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/tao_giao_dich_payos_nap_vi`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_yeu_cau_nap_rut_id: topUpRequestId }),
    })
    const paymentRows = await paymentResponse.json()
    const payment = Array.isArray(paymentRows) ? paymentRows[0] : paymentRows
    if (!paymentResponse.ok || !payment?.ma_don_payos) {
      // Nếu không tạo được mã đơn PayOS thì yêu cầu vừa tạo không phải là
      // khoản đang chờ thanh toán thực tế; đóng nó để không làm lệch số dư chờ.
      await fetch(`${supabaseUrl}/rest/v1/yeu_cau_nap_rut_vi?id=eq.${topUpRequestId}`, {
        method: 'PATCH',
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ trang_thai: 'TU_CHOI', ly_do_tu_choi: 'Không tạo được mã thanh toán PayOS', ngay_xu_ly: new Date().toISOString() }),
      })
      throw new Error(paymentRows?.message ?? 'Không tạo được giao dịch PayOS')
    }

    const orderCode = Number(payment.ma_don_payos)
    const description = `VXN${orderCode}`.slice(0, 9)
    const signatureData = `amount=${amount}&cancelUrl=${cancelUrl}&description=${description}&orderCode=${orderCode}&returnUrl=${returnUrl}`
    const signature = await hmacSha256(signatureData, checksumKey)
    const payosResponse = await fetch('https://api-merchant.payos.vn/v2/payment-requests', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-client-id': clientId, 'x-api-key': apiKey },
      body: JSON.stringify({
        orderCode, amount, description, returnUrl, cancelUrl, signature,
        buyerName: String(user.user_metadata?.ho_ten ?? '').slice(0, 100),
        buyerEmail: String(user.email ?? '').slice(0, 100),
        items: [{ name: 'Nạp ví VinExpress', quantity: 1, price: amount }],
      }),
    })
    const payosResult = await payosResponse.json()
    const payosData = payosResult?.data
    if (!payosResponse.ok || payosResult?.code !== '00' || !payosData?.checkoutUrl) {
      await fetch(`${supabaseUrl}/rest/v1/yeu_cau_nap_rut_vi?ma_don_payos=eq.${orderCode}`, {
        method: 'PATCH',
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ trang_thai: 'TU_CHOI', ly_do_tu_choi: 'PayOS không tạo được liên kết thanh toán', ngay_xu_ly: new Date().toISOString() }),
      })
      throw new Error(payosResult?.desc ?? 'PayOS không tạo được liên kết thanh toán')
    }
    return json({
      checkout_url: payosData.checkoutUrl,
      qr_code: payosData.qrCode,
      order_code: orderCode,
      amount,
    })
  } catch (error) {
    console.error('payos-create-topup:', error)
    return json({ error: error instanceof Error ? error.message : String(error) }, 400)
  }
})
