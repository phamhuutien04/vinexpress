import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = CustomerAuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isEmployee = false;
  String _employeeRole = 'SHIPPER';

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _phoneController,
      _emailController,
      _addressController,
      _passwordController,
      _confirmPasswordController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final email = _isEmployee
          ? await _authService.registerEmployee(
              fullName: _nameController.text,
              phone: _phoneController.text,
              email: _emailController.text,
              password: _passwordController.text,
              employeeRole: _employeeRole,
            )
          : await _authService.register(
              fullName: _nameController.text,
              phone: _phoneController.text,
              email: _emailController.text,
              address: _addressController.text,
              password: _passwordController.text,
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEmployee
              ? 'Đăng ký nhân viên thành công. Vui lòng chờ quản trị viên duyệt tài khoản.'
              : 'Đăng ký thành công. Vui lòng đăng nhập.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, email);
    } on CustomerAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký tài khoản')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isEmployee
                          ? 'Đăng ký tài khoản nhân viên'
                          : 'Tạo tài khoản khách hàng',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isEmployee
                          ? 'Tài khoản sẽ được quản trị viên xét duyệt trước khi đăng nhập.'
                          : 'Nhập thông tin để bắt đầu gửi hàng cùng VinExpress.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Khách hàng'), icon: Icon(Icons.person_outline)),
                        ButtonSegment(value: true, label: Text('Nhân viên'), icon: Icon(Icons.badge_outlined)),
                      ],
                      selected: {_isEmployee},
                      onSelectionChanged: (value) => setState(() => _isEmployee = value.first),
                    ),
                    const SizedBox(height: 20),
                    _field(
                      controller: _nameController,
                      label: 'Họ và tên',
                      icon: Icons.person_outline,
                      validator: _required,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      controller: _phoneController,
                      label: 'Số điện thoại',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        final phone =
                            value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                        return phone.length >= 9 && phone.length <= 11
                            ? null
                            : 'Số điện thoại không hợp lệ';
                      },
                    ),
                    const SizedBox(height: 14),
                    _field(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập email';
                        }
                        return RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(value.trim())
                            ? null
                            : 'Email không hợp lệ';
                      },
                    ),
                    if (_isEmployee) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _employeeRole,
                        decoration: const InputDecoration(
                          labelText: 'Vị trí ứng tuyển',
                          prefixIcon: Icon(Icons.work_outline),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'SHIPPER', child: Text('Shipper')),
                          DropdownMenuItem(value: 'VAN_CHUYEN', child: Text('Nhân viên vận chuyển')),
                          DropdownMenuItem(value: 'NHAN_VIEN_KHO', child: Text('Nhân viên kho')),
                        ],
                        onChanged: (value) => setState(() => _employeeRole = value!),
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      _field(
                        controller: _addressController,
                        label: 'Địa chỉ',
                        icon: Icons.location_on_outlined,
                        maxLines: 2,
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 6
                          ? 'Mật khẩu phải có ít nhất 6 ký tự'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? 'Mật khẩu nhập lại không khớp'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isLoading ? null : _register,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEmployee ? 'Gửi đăng ký nhân viên' : 'Tạo tài khoản'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Vui lòng nhập thông tin' : null;
}
