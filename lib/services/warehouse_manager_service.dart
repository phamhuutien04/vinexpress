import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class WarehouseManagerException implements Exception {
  const WarehouseManagerException(this.message);
  final String message;
}

class WarehouseManagerService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> managedWarehouses() async {
    try {
      final data = await _client.rpc('quan_ly_kho_danh_sach_kho');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw WarehouseManagerException(_message(error));
    }
  }

  Future<Map<String, dynamic>> overview(int warehouseId) async {
    try {
      final data = await _client.rpc(
        'quan_ly_kho_tong_quan_theo_kho',
        params: {'p_kho_id': warehouseId},
      );
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (error) {
      throw WarehouseManagerException(_message(error));
    }
  }

  Future<List<Map<String, dynamic>>> orders(int warehouseId) async {
    try {
      final data = await _client.rpc(
        'quan_ly_kho_don_theo_kho',
        params: {'p_kho_id': warehouseId},
      );
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw WarehouseManagerException(_message(error));
    }
  }

  Future<List<Map<String, dynamic>>> employees(int warehouseId) async {
    try {
      final data = await _client.rpc(
        'quan_ly_kho_nhan_vien_theo_kho',
        params: {'p_kho_id': warehouseId},
      );
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw WarehouseManagerException(_message(error));
    }
  }

  Future<void> createEmployee({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String role,
    required int warehouseId,
    String? licensePlate,
    double? payloadKg,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-create-employee',
        body: {
          'ho_ten': fullName.trim(),
          'so_dien_thoai': phone.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'vai_tro': role,
          'kho_hang_id': warehouseId,
          'bien_so_xe': licensePlate?.trim().toUpperCase(),
          'tai_trong': payloadKg,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        final data = response.data;
        throw WarehouseManagerException(
          data is Map ? '${data['error'] ?? data}' : '$data',
        );
      }
    } on FunctionException catch (error) {
      final details = error.details;
      throw WarehouseManagerException(
        details is Map
            ? '${details['error'] ?? error.reasonPhrase}'
            : '${error.reasonPhrase ?? details}',
      );
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
      throw WarehouseManagerException(_message(error));
    }
  }

  String _message(PostgrestException error) => error.code == 'PGRST202'
      ? 'Chức năng quản lý kho chưa được cài trên Supabase.'
      : error.message;
}
