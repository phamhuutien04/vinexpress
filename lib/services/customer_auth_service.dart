import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

class CustomerAuthException implements Exception {
  const CustomerAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CustomerAuthService {
  CustomerAuthService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  static Map<String, dynamic>? currentCustomer;

  String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const CustomerAuthException('Email hoặc mật khẩu không đúng.');
      }

      final customer = await _client
          .from('khach_hang')
          .select(
            'id, auth_user_id, ho_ten, so_dien_thoai, email, dia_chi, avt, trang_thai',
          )
          .eq('auth_user_id', user.id)
          .single();

      if (customer['trang_thai'] != 'HOAT_DONG') {
        await _client.auth.signOut();
        throw const CustomerAuthException(
          'Tài khoản đang bị khóa hoặc tạm ngưng.',
        );
      }

      currentCustomer = customer;
      return customer;
    } on CustomerAuthException {
      rethrow;
    } on AuthException catch (error) {
      throw CustomerAuthException(_authMessage(error.message));
    } on PostgrestException catch (error) {
      throw CustomerAuthException(
        'Không thể tải hồ sơ khách hàng: ${error.message}',
      );
    } catch (_) {
      throw const CustomerAuthException(
        'Không thể kết nối máy chủ. Vui lòng thử lại.',
      );
    }
  }

  Future<String> register({
    required String fullName,
    required String phone,
    required String password,
    required String email,
    String? address,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final response = await _client.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          'ho_ten': fullName.trim(),
          'so_dien_thoai': _normalizePhone(phone),
          'dia_chi': _nullable(address),
          'vai_tro': 'KHACH_HANG',
        },
      );

      if (response.user == null) {
        throw const CustomerAuthException('Không thể tạo tài khoản.');
      }
      return normalizedEmail;
    } on CustomerAuthException {
      rethrow;
    } on AuthException catch (error) {
      throw CustomerAuthException(_authMessage(error.message));
    } catch (_) {
      throw const CustomerAuthException(
        'Không thể kết nối máy chủ. Vui lòng thử lại.',
      );
    }
  }

  Future<void> logout() async {
    currentCustomer = null;
    await _client.auth.signOut();
  }

  String? _nullable(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  String _authMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login credentials')) {
      return 'Email hoặc mật khẩu không đúng.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'Vui lòng xác nhận email trước khi đăng nhập.';
    }
    if (normalized.contains('already registered') ||
        normalized.contains('already been registered')) {
      return 'Email này đã được đăng ký.';
    }
    if (normalized.contains('password')) {
      return 'Mật khẩu chưa đáp ứng yêu cầu bảo mật.';
    }
    return message;
  }
}
