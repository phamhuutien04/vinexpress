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

  Future<void> claimPickup(int orderId) => _client.rpc(
    'nhan_vien_lay_hang_nhan_don',
    params: {'p_don_hang_id': orderId},
  );

  Future<int> scanDeliveryParcel(String code) async {
    final data = await _client.rpc(
      'nhan_vien_giao_hang_quet_kien',
      params: {'p_ma': code.trim()},
    );
    return (data as num).toInt();
  }
}
