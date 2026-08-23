import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class WalletServiceException implements Exception {
  const WalletServiceException(this.message);
  final String message;
}

class WalletService {
  WalletService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  Future<Map<String, dynamic>> getWalletInfo() async {
    try {
      final data = await _client.rpc('thong_tin_vi');
      final rows = List<Map<String, dynamic>>.from(data as List);
      return rows.isEmpty ? <String, dynamic>{} : rows.first;
    } on PostgrestException catch (error) {
      throw WalletServiceException(error.message);
    }
  }

  Future<List<Map<String, dynamic>>> getTransactions() async {
    try {
      final data = await _client.rpc('lich_su_giao_dich_vi');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw WalletServiceException(error.message);
    }
  }

  Future<int> requestTopUp(double amount) async {
    try {
      final data = await _client.rpc(
        'tao_yeu_cau_nap_vi',
        params: {'p_so_tien': amount, 'p_phuong_thuc': 'CHUYEN_KHOAN'},
      );
      return (data as num).toInt();
    } on PostgrestException catch (error) {
      throw WalletServiceException(error.message);
    }
  }

  Future<int> requestWithdrawal({required double amount}) async {
    try {
      final data = await _client.rpc(
        'tao_yeu_cau_rut_vi',
        params: {'p_so_tien': amount},
      );
      return (data as num).toInt();
    } on PostgrestException catch (error) {
      throw WalletServiceException(error.message);
    }
  }

  Future<void> linkBankAccount({
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    try {
      await _client.rpc(
        'lien_ket_tai_khoan_ngan_hang_vi',
        params: {
          'p_ngan_hang': bankName,
          'p_so_tai_khoan': accountNumber,
          'p_chu_tai_khoan': accountHolder,
        },
      );
    } on PostgrestException catch (error) {
      throw WalletServiceException(error.message);
    }
  }

  Future<Map<String, dynamic>?> getLinkedBankAccount() async {
    try {
      final data = await _client.rpc('thong_tin_tai_khoan_ngan_hang_vi');
      final rows = List<Map<String, dynamic>>.from(data as List);
      return rows.isEmpty ? null : rows.first;
    } on PostgrestException catch (error) {
      throw WalletServiceException(error.message);
    }
  }
}
