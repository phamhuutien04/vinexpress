import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

class LastMileStaffService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> tasks() async {
    final data = await _client.rpc('nhan_vien_chang_cuoi_cong_viec_v2');
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<String> confirm(int orderId) async =>
      '${await _client.rpc('nhan_vien_chang_cuoi_xac_nhan', params: {'p_don_hang_id': orderId})}';

  Future<String> confirmPickupWithEvidence({
    required int orderId,
    required String evidenceUrl,
    required double latitude,
    required double longitude,
    required double pickupLatitude,
    required double pickupLongitude,
  }) async =>
      '${await _client.rpc('nhan_vien_lay_hang_xac_nhan_minh_chung', params: {'p_don_hang_id': orderId, 'p_minh_chung': evidenceUrl, 'p_vi_do': latitude, 'p_kinh_do': longitude, 'p_diem_lay_vi_do': pickupLatitude, 'p_diem_lay_kinh_do': pickupLongitude})}';

  Future<void> claimPickup(int orderId) => _client.rpc(
    'nhan_vien_lay_hang_nhan_don',
    params: {'p_don_hang_id': orderId},
  );

  Future<Map<String, dynamic>?> pickupCoordinates(int orderId) async {
    try {
      final data = await _client.rpc(
        'toa_do_diem_lay_nhan_vien',
        params: {'p_don_hang_id': orderId},
      );
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {
      // Tương thích tạm thời với database chưa chạy bản vá mới.
    }
    final row = await _client
        .from('don_hang')
        .select('nguoi_gui_vi_do,nguoi_gui_kinh_do')
        .eq('id', orderId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<String?> currentWarehouseAddress() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final employee = await _client
        .from('nhan_vien')
        .select('kho_hang_id')
        .eq('auth_user_id', userId)
        .maybeSingle();
    final warehouseId = employee?['kho_hang_id'];
    if (warehouseId == null) return null;
    final warehouse = await _client
        .from('kho_hang')
        .select('dia_chi,cap_kho')
        .eq('id', warehouseId)
        .maybeSingle();
    if (warehouse == null || warehouse['cap_kho'] != 2) return null;
    final address = '${warehouse['dia_chi'] ?? ''}'.trim();
    return address.isEmpty ? null : address;
  }

  Future<int> scanDeliveryParcel(String code) async {
    final data = await _client.rpc(
      'nhan_vien_giao_hang_quet_kien',
      params: {'p_ma': code.trim()},
    );
    return (data as num).toInt();
  }
}
