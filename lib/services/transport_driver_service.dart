import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class TransportDriverException implements Exception {
  const TransportDriverException(this.message);
  final String message;
}

class TransportDriverService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final data = await _client.rpc('thong_tin_tai_xe_van_chuyen');
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (error) {
      throw TransportDriverException(_message(error));
    }
  }

  Future<List<Map<String, dynamic>>> getTrips() async {
    try {
      final data = await _client.rpc('chuyen_xe_cua_tai_xe_co_chang');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw TransportDriverException(_message(error));
    }
  }

  Future<void> updateTrip(int tripId, String status) async {
    try {
      await _client.rpc(
        'cap_nhat_chuyen_xe_tai_xe',
        params: {'p_chuyen_xe_id': tripId, 'p_trang_thai_moi': status},
      );
    } on PostgrestException catch (error) {
      throw TransportDriverException(_message(error));
    }
  }

  String _message(PostgrestException error) {
    if (error.code == 'PGRST202') {
      return 'Chức năng lộ trình tài xế chưa được cài trên Supabase. Hãy chạy patch_transport_driver_route_stages.sql.';
    }
    return error.message;
  }
}
