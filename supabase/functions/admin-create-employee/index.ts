const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Chỉ hỗ trợ POST' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authorization = request.headers.get('Authorization') ?? ''
  let createdUserId = null

  try {
    if (!supabaseUrl || !anonKey || !serviceKey) throw new Error('Edge Function thiếu biến môi trường Supabase')
    if (!authorization.startsWith('Bearer ')) throw new Error('Thiếu phiên đăng nhập')

    const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: authorization },
    })
    const user = await userResponse.json()
    if (!userResponse.ok || !user.id) throw new Error('Phiên đăng nhập không hợp lệ')

    const creatorUrl = new URL(`${supabaseUrl}/rest/v1/nhan_vien`)
    creatorUrl.searchParams.set('select', 'id,vai_tro,kho_hang_id')
    creatorUrl.searchParams.set('auth_user_id', `eq.${user.id}`)
    creatorUrl.searchParams.set('trang_thai_duyet', 'eq.DA_DUYET')
    creatorUrl.searchParams.set('trang_thai', 'eq.HOAT_DONG')
    creatorUrl.searchParams.set('limit', '1')
    const creatorResponse = await fetch(creatorUrl, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
    })
    const creators = await creatorResponse.json()
    const creator = Array.isArray(creators) ? creators[0] : null
    if (!creatorResponse.ok || !creator || !['ADMIN', 'QUAN_LY_KHO'].includes(creator.vai_tro)) {
      throw new Error('Bạn không có quyền tạo tài khoản nhân viên')
    }

    const body = await request.json()
    const email = String(body.email ?? '').trim().toLowerCase()
    const password = String(body.password ?? '')
    const hoTen = String(body.ho_ten ?? '').trim()
    const soDienThoai = String(body.so_dien_thoai ?? '').replace(/[^0-9+]/g, '')
    const vaiTro = String(body.vai_tro ?? '').toUpperCase()
    const bienSoXe = String(body.bien_so_xe ?? '').trim().toUpperCase()
    const taiTrong = Number(body.tai_trong ?? 0)
    let khoHangId = body.kho_hang_id == null ? null : Number(body.kho_hang_id)

    if (!email || !hoTen || !soDienThoai || password.length < 6) throw new Error('Thông tin chưa đầy đủ hoặc mật khẩu dưới 6 ký tự')
    if (!['QUAN_LY_KHO', 'NHAN_VIEN_KHO', 'VAN_CHUYEN', 'SHIPPER'].includes(vaiTro)) throw new Error('Vai trò nhân viên không hợp lệ')
    if (creator.vai_tro === 'QUAN_LY_KHO') {
      if (!creator.kho_hang_id) throw new Error('Quản lý chưa được gán kho')
      if (!['QUAN_LY_KHO', 'NHAN_VIEN_KHO', 'VAN_CHUYEN'].includes(vaiTro)) throw new Error('Vai trò không thuộc quyền của quản lý kho')
      khoHangId = khoHangId ?? Number(creator.kho_hang_id)
      const scopeUrl = new URL(`${supabaseUrl}/rest/v1/kho_hang`)
      scopeUrl.searchParams.set('select', 'id,cap_kho,kho_trung_tam_id')
      scopeUrl.searchParams.set('id', `eq.${khoHangId}`)
      scopeUrl.searchParams.set('or', `(id.eq.${creator.kho_hang_id},kho_trung_tam_id.eq.${creator.kho_hang_id})`)
      scopeUrl.searchParams.set('limit', '1')
      const scopeResponse = await fetch(scopeUrl, {
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      })
      const scopeRows = await scopeResponse.json()
      if (!scopeResponse.ok || !Array.isArray(scopeRows) || scopeRows.length === 0) {
        throw new Error('Kho được chọn không thuộc phạm vi quản lý')
      }
      if (vaiTro === 'QUAN_LY_KHO' &&
          (Number(scopeRows[0].cap_kho) !== 2 || Number(scopeRows[0].kho_trung_tam_id) !== Number(creator.kho_hang_id))) {
        throw new Error('Chỉ được tạo quản lý cho kho cấp 2 trực thuộc')
      }
    }
    if (['QUAN_LY_KHO', 'NHAN_VIEN_KHO'].includes(vaiTro) && (!khoHangId || khoHangId <= 0)) throw new Error('Nhân viên phải được gán kho làm việc')
    if (vaiTro === 'VAN_CHUYEN' && (!bienSoXe || !Number.isFinite(taiTrong) || taiTrong <= 0)) throw new Error('Tài xế phải có biển số và tải trọng hợp lệ')

    const authResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
      method: 'POST',
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          ho_ten: hoTen,
          so_dien_thoai: soDienThoai,
          vai_tro: 'NHAN_VIEN',
          vai_tro_nhan_vien: vaiTro,
          admin_tao_ho_so: true,
        },
      }),
    })
    const authData = await authResponse.json()
    if (!authResponse.ok || !authData.id) throw new Error(authData.message ?? authData.msg ?? 'Không tạo được tài khoản Auth')
    createdUserId = authData.id

    const profileResponse = await fetch(`${supabaseUrl}/rest/v1/nhan_vien?select=id`, {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        auth_user_id: createdUserId,
        kho_hang_id: khoHangId,
        ho_ten: hoTen,
        so_dien_thoai: soDienThoai,
        email,
        mat_khau: 'SUPABASE_AUTH',
        vai_tro: vaiTro,
        trang_thai_duyet: 'DA_DUYET',
        trang_thai: 'HOAT_DONG',
      }),
    })
    const profiles = await profileResponse.json()
    const employee = Array.isArray(profiles) ? profiles[0] : null
    if (!profileResponse.ok || !employee?.id) throw new Error(profiles.message ?? profiles.details ?? 'Không tạo được hồ sơ nhân viên')

    if (vaiTro === 'VAN_CHUYEN') {
      const vehicleResponse = await fetch(`${supabaseUrl}/rest/v1/xe`, {
        method: 'POST',
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ tai_xe_id: employee.id, bien_so_xe: bienSoXe, tai_trong: taiTrong, trang_thai: 'SAN_SANG' }),
      })
      if (!vehicleResponse.ok) {
        const vehicleError = await vehicleResponse.json()
        throw new Error(vehicleError.message ?? 'Không tạo được xe tải')
      }
    }

    return json({ ok: true, user_id: createdUserId })
  } catch (error) {
    if (createdUserId && serviceKey && supabaseUrl) {
      await fetch(`${supabaseUrl}/auth/v1/admin/users/${createdUserId}`, {
        method: 'DELETE',
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      }).catch(() => null)
    }
    console.error('admin-create-employee:', error)
    return json({ error: error instanceof Error ? error.message : String(error) }, 400)
  }
})
