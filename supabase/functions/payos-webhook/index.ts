const deno = (globalThis as typeof globalThis & {
  Deno: { serve: (handler: (request: Request) => Response | Promise<Response>) => void; env: { get: (name: string) => string | undefined } }
}).Deno

function valueForSignature(value: unknown) {
  if (value === null || value === undefined || value === 'null' || value === 'undefined') return ''
  if (Array.isArray(value)) return JSON.stringify(value.map((item) => sortObject(item as Record<string, unknown>)))
  return String(value)
}

function sortObject(value: Record<string, unknown>) {
  return Object.keys(value).sort().reduce<Record<string, unknown>>((result, key) => {
    result[key] = value[key]
    return result
  }, {})
}

async function hmacSha256(value: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value))
  return Array.from(new Uint8Array(signature)).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

deno.serve(async (request) => {
  if (request.method !== 'POST') return reply({ error: 'Chỉ hỗ trợ POST' }, 405)
  const supabaseUrl = deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const checksumKey = deno.env.get('PAYOS_CHECKSUM_KEY') ?? ''
  try {
    if (!supabaseUrl || !serviceKey || !checksumKey) throw new Error('Thiếu Secrets PayOS')
    const payload = await request.json()
    const data = payload?.data as Record<string, unknown> | undefined
    if (!payload?.signature || !data) throw new Error('Webhook PayOS không hợp lệ')
    const signatureSource = Object.keys(data).sort().map((key) => `${key}=${valueForSignature(data[key])}`).join('&')
    const expectedSignature = await hmacSha256(signatureSource, checksumKey)
    if (expectedSignature.toLowerCase() !== String(payload.signature).toLowerCase()) {
      return reply({ error: 'Chữ ký PayOS không hợp lệ' }, 400)
    }
    if (payload.success !== true || data.code !== '00') return reply({ ok: true })
    // Lúc xác nhận webhook, PayOS gửi một giao dịch mẫu không thuộc hệ thống.
    // Chữ ký đã hợp lệ nên phản hồi 2xx để PayOS hoàn tất kiểm tra, nhưng tuyệt
    // đối không tạo hay cộng tiền cho một mã đơn không tồn tại trong VinExpress.
    const existingPayment = await fetch(
      `${supabaseUrl}/rest/v1/giao_dich_payos?ma_don_payos=eq.${Number(data.orderCode)}&select=id&limit=1`,
      { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
    )
    const existingRows = await existingPayment.json()
    if (!existingPayment.ok) throw new Error(existingRows?.message ?? 'Không kiểm tra được giao dịch PayOS')
    if (!Array.isArray(existingRows) || existingRows.length === 0) return reply({ ok: true })
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/xac_nhan_giao_dich_payos_nap_vi`, {
      method: 'POST',
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        p_ma_don_payos: Number(data.orderCode),
        p_payment_link_id: String(data.paymentLinkId ?? ''),
        p_ma_tham_chieu: String(data.reference ?? ''),
        p_so_tien: Number(data.amount),
        p_du_lieu_webhook: payload,
      }),
    })
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.message ?? 'Không thể ghi nhận thanh toán')
    }
    return reply({ ok: true })
  } catch (error) {
    console.error('payos-webhook:', error)
    return reply({ error: error instanceof Error ? error.message : String(error) }, 400)
  }
})
