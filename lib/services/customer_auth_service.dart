import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

class CustomerAuthException implements Exception {
  const CustomerAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum AccountType { customer, employee }

class LoginResult {
  const LoginResult({required this.type, required this.profile});

  final AccountType type;
  final Map<String, dynamic> profile;
}

class CustomerAuthService {
  CustomerAuthService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  static Map<String, dynamic>? currentCustomer;
  static Map<String, dynamic>? currentEmployee;

  String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<LoginResult> login({
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

      try {
        final customer = await _client
            .from('khach_hang')
            .select('id, auth_user_id, ho_ten, so_dien_thoai, email, dia_chi, avt, trang_thai')
            .eq('auth_user_id', user.id)
            .single();
        if (customer['trang_thai'] != 'HOAT_DONG') {
          throw const CustomerAuthException('Tài khoản khách hàng đang bị khóa.');
        }
        currentCustomer = Map<String, dynamic>.from(customer);
        currentEmployee = null;
        return LoginResult(type: AccountType.customer, profile: currentCustomer!);
      } on PostgrestException {
        final employee = await _client
            .from('nhan_vien')
            .select('id, auth_user_id, ho_ten, so_dien_thoai, email, kho_hang_id, vai_tro, trang_thai, trang_thai_duyet')
            .eq('auth_user_id', user.id)
            .single();
        if (employee['trang_thai'] != 'HOAT_DONG' ||
            employee['trang_thai_duyet'] != 'DA_DUYET') {
          await _client.auth.signOut();
          throw const CustomerAuthException('Tài khoản nhân viên chưa được duyệt hoặc đã bị khóa.');
        }
        currentEmployee = Map<String, dynamic>.from(employee);
        currentCustomer = null;
        return LoginResult(type: AccountType.employee, profile: currentEmployee!);
      }
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

  /// Registers an employee account. Employee accounts stay pending until an
  /// administrator approves them in the `nhan_vien` table.
  Future<String> registerEmployee({
    required String fullName,
    required String phone,
    required String password,
    required String email,
    required String employeeRole,
  }) async {
    const allowedRoles = {'NHAN_VIEN_KHO', 'VAN_CHUYEN', 'SHIPPER'};
    if (!allowedRoles.contains(employeeRole)) {
      throw const CustomerAuthException('Vai trò nhân viên không hợp lệ.');
    }

    try {
      final normalizedEmail = email.trim().toLowerCase();
      final response = await _client.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          'ho_ten': fullName.trim(),
          'so_dien_thoai': _normalizePhone(phone),
          'vai_tro': 'NHAN_VIEN',
          'vai_tro_nhan_vien': employeeRole,
        },
      );
      if (response.user == null) {
        throw const CustomerAuthException('Không thể tạo tài khoản nhân viên.');
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
    currentEmployee = null;
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
    if (normalized.contains('database error saving new user') ||
        normalized.contains('unexpected_failure')) {
      return 'Máy chủ chưa tạo được hồ sơ nhân viên. Vui lòng chạy file '
          'supabase/employee_auth_setup.sql trong Supabase SQL Editor.';
    }
    return message;
  }
}
