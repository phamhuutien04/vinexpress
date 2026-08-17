import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) throw new Error('Thiếu phiên đăng nhập Admin')

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) throw new Error('Phiên đăng nhập không hợp lệ')

    const { data: adminProfile } = await adminClient
      .from('nhan_vien')
      .select('id')
      .eq('auth_user_id', userData.user.id)
      .eq('vai_tro', 'ADMIN')
      .eq('trang_thai_duyet', 'DA_DUYET')
      .eq('trang_thai', 'HOAT_DONG')
      .maybeSingle()
    if (!adminProfile) throw new Error('Chỉ ADMIN mới được tạo tài khoản nhân viên')

    const body = await request.json()
    const email = String(body.email ?? '').trim().toLowerCase()
    const password = String(body.password ?? '')
    const hoTen = String(body.ho_ten ?? '').trim()
    const soDienThoai = String(body.so_dien_thoai ?? '').replace(/[^0-9+]/g, '')
    const vaiTro = String(body.vai_tro ?? '').toUpperCase()
    const khoHangId = body.kho_hang_id == null ? null : Number(body.kho_hang_id)
    const bienSoXe = String(body.bien_so_xe ?? '').trim().toUpperCase()
    const taiTrong = Number(body.tai_trong ?? 0)
    const allowedRoles = ['QUAN_LY_KHO', 'NHAN_VIEN_KHO', 'VAN_CHUYEN', 'SHIPPER']

    if (!email || !hoTen || !soDienThoai || password.length < 6) {
      throw new Error('Thông tin nhân viên chưa đầy đủ hoặc mật khẩu dưới 6 ký tự')
    }
    if (!allowedRoles.includes(vaiTro)) throw new Error('Vai trò nhân viên không hợp lệ')
    if (vaiTro === 'VAN_CHUYEN' && (!bienSoXe || !Number.isFinite(taiTrong) || taiTrong <= 0)) {
      throw new Error('Tài xế xe tải phải có biển số và tải trọng hợp lệ')
    }

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        ho_ten: hoTen,
        so_dien_thoai: soDienThoai,
        vai_tro: 'NHAN_VIEN',
        vai_tro_nhan_vien: vaiTro,
      },
    })
    if (createError) throw createError

    const { data: employee, error: updateError } = await adminClient
      .from('nhan_vien')
      .update({
        trang_thai_duyet: 'DA_DUYET',
        trang_thai: 'HOAT_DONG',
        kho_hang_id: khoHangId,
      })
      .eq('auth_user_id', created.user.id)
      .select('id')
      .single()
    if (updateError || !employee) {
      await adminClient.auth.admin.deleteUser(created.user.id)
      throw updateError ?? new Error(
        'Không tạo được hồ sơ trong bảng nhan_vien. Hãy chạy employee_auth_setup.sql.',
      )
    }

    if (vaiTro === 'VAN_CHUYEN') {
      const { error: vehicleError } = await adminClient.from('xe').insert({
        tai_xe_id: employee.id,
        bien_so_xe: bienSoXe,
        tai_trong: taiTrong,
        trang_thai: 'SAN_SANG',
      })
      if (vehicleError) {
        await adminClient.auth.admin.deleteUser(created.user.id)
        throw vehicleError
      }
    }

    return new Response(JSON.stringify({ ok: true, user_id: created.user.id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    console.error('admin-create-employee:', error)
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
