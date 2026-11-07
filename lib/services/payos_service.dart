import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class PayosServiceException implements Exception {
  const PayosServiceException(this.message);
  final String message;
}

class PayosCheckout {
  const PayosCheckout({
    required this.checkoutUrl,
    required this.qrCode,
    required this.orderCode,
    required this.amount,
  });

  final String checkoutUrl;
  final String? qrCode;
  final int orderCode;
  final int amount;
}

class PayosService {
  PayosService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  Future<PayosCheckout> createWalletTopUp({required int amount}) async {
    try {
      final result = await _client.functions.invoke(
        'payos-create-topup',
        body: {'amount': amount},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['error'] != null || data['checkout_url'] == null) {
        throw PayosServiceException(
          '${data['error'] ?? 'Không tạo được liên kết thanh toán'}',
        );
      }
      return PayosCheckout(
        checkoutUrl: '${data['checkout_url']}',
        qrCode: data['qr_code']?.toString(),
        orderCode: (data['order_code'] as num).toInt(),
        amount: (data['amount'] as num).toInt(),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw PayosServiceException('${message ?? 'Không kết nối được dịch vụ thanh toán'}');
    } catch (error) {
      if (error is PayosServiceException) rethrow;
      throw const PayosServiceException(
        'Không kết nối được dịch vụ thanh toán. Vui lòng thử lại.',
      );
    }
  }

  Future<bool> isPaymentCompleted(int orderCode) async {
    try {
      final data = await _client.rpc(
        'trang_thai_giao_dich_payos',
        params: {'p_ma_don_payos': orderCode},
      );
      final rows = List<Map<String, dynamic>>.from(data as List);
      return rows.isNotEmpty && rows.first['trang_thai'] == 'DA_THANH_TOAN';
    } on PostgrestException catch (error) {
      throw PayosServiceException(error.message);
    }
  }

  Future<void> cancelWalletTopUp(int orderCode) async {
    try {
      final result = await _client.functions.invoke(
        'payos-cancel-topup',
        body: {'order_code': orderCode},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['error'] != null || data['ok'] != true) {
        throw PayosServiceException(
          '${data['error'] ?? 'Không thể hủy giao dịch thanh toán'}',
        );
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw PayosServiceException(
        '${message ?? 'Không thể hủy giao dịch thanh toán'}',
      );
    }
  }
}
