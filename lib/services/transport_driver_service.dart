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

  Future<List<Map<String, dynamic>>> getIncidents() async {
    try {
      final data = await _client.rpc('tai_xe_danh_sach_su_co');
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

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    try {
      await _client.rpc(
        'cap_nhat_vi_tri_tai_xe_van_chuyen',
        params: {
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
          'p_do_chinh_xac_met': accuracyMeters,
        },
      );
    } on PostgrestException catch (error) {
      throw TransportDriverException(_message(error));
    }
  }

  Future<int> reportIncident({
    required int tripId,
    required String type,
    required String description,
    required String evidenceUrl,
  }) async {
    try {
      final data = await _client.rpc(
        'tai_xe_bao_cao_su_co',
        params: {
          'p_chuyen_xe_id': tripId,
          'p_loai_su_co': type,
          'p_mo_ta': description.trim(),
          'p_anh_minh_chung_url': evidenceUrl,
        },
      );
      return (data as num).toInt();
    } on PostgrestException catch (error) {
      throw TransportDriverException(_message(error));
    }
  }

  String _message(PostgrestException error) {
    if (error.code == 'PGRST202') {
      return 'Chức năng tài xế chưa được cài đủ trên Supabase. Hãy chạy patch_transport_driver_route_stages.sql và patch_transport_incident_reports.sql.';
    }
    return error.message;
  }
}
