import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class WarehouseEmployeeException implements Exception {
  const WarehouseEmployeeException(this.message);
  final String message;
}

class WarehouseEmployeeService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<Map<String, dynamic>> level2CreationPermission() async {
    try {
      final data = await _client.rpc('thong_tin_quyen_tao_kho_cap_2');
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }

  Future<Map<String, dynamic>> overview() async {
    try {
      final data = await _client.rpc('nhan_vien_kho_tong_quan');
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }

  Future<List<Map<String, dynamic>>> assignedOrders() async {
    try {
      final data = await _client.rpc('nhan_vien_kho_don_can_xu_ly');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }

  Future<List<Map<String, dynamic>>> trips() async {
    try {
      final data = await _client.rpc('nhan_vien_kho_danh_sach_chuyen');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }

  Future<String> scanParcel({
    required int tripId,
    required String code,
    required String action,
  }) async {
    try {
      final data = await _client.rpc(
        'nhan_vien_kho_quet_kien_chuyen',
        params: {
          'p_chuyen_xe_id': tripId,
          'p_ma': code.trim(),
          'p_thao_tac': action,
        },
      );
      return '$data';
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }

  Future<String> receiveParcel(String code) async {
    try {
      final data = await _client.rpc(
        'nhan_vien_kho_nhap_kien',
        params: {'p_ma': code.trim()},
      );
      return '$data';
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }

  Future<void> createLevel2Warehouse({
    required String name,
    required String address,
    required String province,
    required String ward,
    String? phone,
  }) async {
    try {
      await _client.rpc('nhan_vien_tao_kho_cap_2', params: {
        'p_ten_kho': name.trim(),
        'p_dia_chi': address.trim(),
        'p_tinh_thanh': province.trim(),
        'p_phuong_xa': ward.trim(),
        'p_so_dien_thoai': phone?.trim(),
      });
    } on PostgrestException catch (error) {
      throw WarehouseEmployeeException(error.message);
    }
  }
}
