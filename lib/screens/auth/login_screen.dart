import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../admin/admin_home_screen.dart';
import '../customer/customer_home_screen.dart';
import '../employee/delivery_home_screen.dart';
import '../employee/employee_home_screen.dart';
import '../employee/last_mile_staff_screen.dart';
import '../transport/transport_driver_home_screen.dart';
import '../warehouse/warehouse_manager_home_screen.dart';
import 'register_screen.dart';
import 'widgets/auth_design.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = CustomerAuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final result = await _authService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) {
            if (result.type == AccountType.customer) {
              return const CustomerHomeScreen();
            }
            final role = result.profile['vai_tro'] as String?;
            if (role == 'ADMIN') return const AdminHomeScreen();
            if (role == 'SHIPPER') return const DeliveryHomeScreen();
            if (role == 'NHAN_VIEN_LAY_HANG' || role == 'NHAN_VIEN_GIAO_HANG') {
              return const LastMileStaffScreen();
            }
            if (role == 'VAN_CHUYEN') {
              return const TransportDriverHomeScreen();
            }
            if (role == 'QUAN_LY_KHO') {
              return const WarehouseManagerHomeScreen();
            }
            return const EmployeeHomeScreen();
          },
        ),
      );
    } on CustomerAuthException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _openRegister() async {
    final email = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (email != null) _emailController.text = email;
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Chào mừng trở lại',
      subtitle: 'Đăng nhập để tiếp tục quản lý hành trình giao hàng của bạn.',
      form: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: 'Email',
                hint: 'tenban@email.com',
                controller: _emailController,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                    return 'Email không hợp lệ';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              AuthField(
                label: 'Mật khẩu',
                hint: 'Nhập mật khẩu',
                controller: _passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _login(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Mật khẩu phải có ít nhất 6 ký tự';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 26),
              AuthPrimaryButton(
                label: 'Đăng nhập',
                loading: _isLoading,
                onPressed: _login,
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    'Chưa có tài khoản?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _openRegister,
                    child: const Text(
                      'Đăng ký ngay',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
