import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import 'widgets/auth_design.dart';

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
  bool _obscureConfirmPassword = true;
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
          content: Text(
            _isEmployee
                ? 'Đăng ký nhân viên thành công. Vui lòng chờ quản trị viên duyệt tài khoản.'
                : 'Đăng ký thành công. Vui lòng đăng nhập.',
          ),
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
    final title = _isEmployee
        ? 'Đăng ký tài khoản nhân viên'
        : 'Tạo tài khoản khách hàng';
    final subtitle = _isEmployee
        ? 'Gửi thông tin để quản trị viên xét duyệt tài khoản của bạn.'
        : 'Tạo tài khoản để bắt đầu gửi và theo dõi đơn hàng.';

    return AuthPageShell(
      title: title,
      subtitle: subtitle,
      showBackButton: true,
      form: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AccountTypeSelector(
                isEmployee: _isEmployee,
                enabled: !_isLoading,
                onChanged: (value) => setState(() => _isEmployee = value),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, 'Thông tin cá nhân'),
              const SizedBox(height: 16),
              AuthField(
                label: 'Họ và tên',
                hint: 'Nhập họ và tên',
                controller: _nameController,
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: _required,
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Số điện thoại',
                hint: 'Nhập số điện thoại',
                controller: _phoneController,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                validator: (value) {
                  final phone = value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                  return phone.length >= 9 && phone.length <= 11
                      ? null
                      : 'Số điện thoại không hợp lệ';
                },
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Email',
                hint: 'tenban@email.com',
                controller: _emailController,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
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
                const SizedBox(height: 16),
                _EmployeeRoleField(
                  value: _employeeRole,
                  onChanged: (value) => setState(() => _employeeRole = value),
                ),
                const SizedBox(height: 14),
                const AuthInfoStrip(
                  icon: Icons.schedule_outlined,
                  text:
                      'Tài khoản nhân viên cần được quản trị viên duyệt trước khi đăng nhập.',
                ),
              ] else ...[
                const SizedBox(height: 16),
                AuthField(
                  label: 'Địa chỉ',
                  hint: 'Nhập địa chỉ hiện tại',
                  controller: _addressController,
                  icon: Icons.location_on_outlined,
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.fullStreetAddress],
                ),
              ],
              const SizedBox(height: 26),
              _sectionTitle(context, 'Bảo mật tài khoản'),
              const SizedBox(height: 16),
              AuthField(
                label: 'Mật khẩu',
                hint: 'Tối thiểu 6 ký tự',
                controller: _passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
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
                validator: (value) => value == null || value.length < 6
                    ? 'Mật khẩu phải có ít nhất 6 ký tự'
                    : null,
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Nhập lại mật khẩu',
                hint: 'Nhập lại mật khẩu',
                controller: _confirmPasswordController,
                icon: Icons.verified_user_outlined,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _register(),
                suffixIcon: IconButton(
                  tooltip: _obscureConfirmPassword
                      ? 'Hiện mật khẩu'
                      : 'Ẩn mật khẩu',
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                validator: (value) => value != _passwordController.text
                    ? 'Mật khẩu nhập lại không khớp'
                    : null,
              ),
              const SizedBox(height: 26),
              AuthPrimaryButton(
                label: _isEmployee ? 'Gửi đăng ký nhân viên' : 'Tạo tài khoản',
                loading: _isLoading,
                onPressed: _register,
                icon: _isEmployee
                    ? Icons.send_outlined
                    : Icons.person_add_alt_1_rounded,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Đã có tài khoản? Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Vui lòng nhập thông tin' : null;
}

class _AccountTypeSelector extends StatelessWidget {
  const _AccountTypeSelector({
    required this.isEmployee,
    required this.enabled,
    required this.onChanged,
  });

  final bool isEmployee;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 330;
      if (compact) {
        return Container(
          height: 50,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: _CompactAccountButton(
                  label: 'Khách hàng',
                  selected: !isEmployee,
                  enabled: enabled,
                  onPressed: () => onChanged(false),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _CompactAccountButton(
                  label: 'Nhân viên',
                  selected: isEmployee,
                  enabled: enabled,
                  onPressed: () => onChanged(true),
                ),
              ),
            ],
          ),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              label: const Text('Khách hàng'),
              icon: compact ? null : const Icon(Icons.person_outline_rounded),
            ),
            ButtonSegment(
              value: true,
              label: const Text('Nhân viên'),
              icon: compact ? null : const Icon(Icons.badge_outlined),
            ),
          ],
          selected: {isEmployee},
          onSelectionChanged: enabled
              ? (value) => onChanged(value.first)
              : null,
          style: ButtonStyle(
            visualDensity: VisualDensity.comfortable,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 14, horizontal: compact ? 8 : 18),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    },
  );
}

class _CompactAccountButton extends StatelessWidget {
  const _CompactAccountButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: enabled ? onPressed : null,
    style: TextButton.styleFrom(
      backgroundColor: selected ? AppColors.primary : Colors.transparent,
      foregroundColor: selected
          ? const Color(0xFF082F2B)
          : Theme.of(context).colorScheme.onSurfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class _EmployeeRoleField extends StatelessWidget {
  const _EmployeeRoleField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vị trí ứng tuyển',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.work_outline_rounded),
            filled: true,
            fillColor: colors.surfaceContainerLowest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.outlineVariant),
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'SHIPPER', child: Text('Shipper')),
            DropdownMenuItem(
              value: 'VAN_CHUYEN',
              child: Text('Nhân viên vận chuyển'),
            ),
            DropdownMenuItem(
              value: 'NHAN_VIEN_KHO',
              child: Text('Nhân viên kho'),
            ),
          ],
          onChanged: (nextValue) {
            if (nextValue != null) onChanged(nextValue);
          },
        ),
      ],
    );
  }
}
