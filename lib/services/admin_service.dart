import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class AdminServiceException implements Exception {
  const AdminServiceException(this.message);
  final String message;
}

class AdminService {
  AdminService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  Future<Map<String, dynamic>> getOverview() async {
    try {
      final data = await _client.rpc('admin_tong_quan');
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (error) {
      throw AdminServiceException(_message(error));
    }
  }

  Future<List<Map<String, dynamic>>> getEmployees() =>
      _list('admin_danh_sach_nhan_vien');

  Future<List<Map<String, dynamic>>> getCustomers() =>
      _list('admin_danh_sach_khach_hang');

  Future<List<Map<String, dynamic>>> getOrders() =>
      _list('admin_danh_sach_don_hang');

  Future<List<Map<String, dynamic>>> getWarehouses() =>
      _list('admin_danh_sach_kho');

  Future<List<Map<String, dynamic>>> getRegions() =>
      _list('admin_danh_sach_khu_vuc');

  Future<List<Map<String, dynamic>>> _list(String function) async {
    try {
      final data = await _client.rpc(function);
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw AdminServiceException(_message(error));
    }
  }

  Future<void> updateEmployee({
    required int employeeId,
    String? approvalStatus,
    String? accountStatus,
  }) async {
    try {
      await _client.rpc(
        'admin_cap_nhat_nhan_vien',
        params: {
          'p_nhan_vien_id': employeeId,
          'p_trang_thai_duyet': approvalStatus,
          'p_trang_thai': accountStatus,
        },
      );
    } on PostgrestException catch (error) {
      throw AdminServiceException(_message(error));
    }
  }

  Future<void> createEmployee({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String role,
    int? warehouseId,
    int? regionId,
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
          'khu_vuc_id': regionId,
          'bien_so_xe': licensePlate?.trim().toUpperCase(),
          'tai_trong': payloadKg,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        final data = response.data;
        final message = data is Map ? '${data['error'] ?? data}' : '$data';
        throw AdminServiceException(message);
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map
          ? '${details['error'] ?? error.reasonPhrase}'
          : '${error.reasonPhrase ?? details}';
      throw AdminServiceException(message);
    }
  }

  Future<void> createWarehouse({
    required String name,
    required String address,
    required String province,
    required String ward,
    required int level,
    String? phone,
    int? parentWarehouseId,
  }) async {
    try {
      await _client.rpc(
        'admin_tao_kho',
        params: {
          'p_ten_kho': name.trim(),
          'p_dia_chi': address.trim(),
          'p_tinh_thanh': province.trim(),
          'p_phuong_xa': ward.trim(),
          'p_so_dien_thoai': phone?.trim(),
          'p_cap_kho': level,
          'p_kho_trung_tam_id': level == 2 ? parentWarehouseId : null,
        },
      );
    } on PostgrestException catch (error) {
      throw AdminServiceException(_message(error));
    }
  }

  String _message(PostgrestException error) {
    if (error.code == 'PGRST202' || error.message.contains('admin_')) {
      return 'Chức năng Admin chưa được cài trên Supabase. '
          'Hãy chạy file admin_setup.sql.';
    }
    return error.message;
  }
}
