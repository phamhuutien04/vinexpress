import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../auth/login_screen.dart';
import '../wallet/bank_account_screen.dart';
import 'widgets/customer_design.dart';

class CustomerAccountScreen extends StatelessWidget {
  const CustomerAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final customer = CustomerAuthService.currentCustomer ?? const {};
    final name = '${customer['ho_ten'] ?? 'Khách hàng'}';
    final email = '${customer['email'] ?? ''}';
    final phone = '${customer['so_dien_thoai'] ?? ''}';

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: CustomerUi.pagePadding(constraints.maxWidth),
          children: [
            CustomerConstrained(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileHeader(name: name, phone: phone, email: email),
                  const SizedBox(height: 28),
                  const CustomerSectionHeader(title: 'Thông tin tài khoản'),
                  const SizedBox(height: 12),
                  CustomerPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _AccountTile(
                          icon: Icons.person_outline_rounded,
                          title: 'Thông tin cá nhân',
                          subtitle: 'Tên, số điện thoại và địa chỉ',
                          onTap: () => _showProfile(context, customer),
                        ),
                        _divider(context),
                        _AccountTile(
                          icon: Icons.account_balance_outlined,
                          title: 'Tài khoản ngân hàng',
                          subtitle: 'Nhận tiền khi rút ví',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BankAccountScreen(),
                            ),
                          ),
                        ),
                        _divider(context),
                        _AccountTile(
                          icon: Icons.lock_outline_rounded,
                          title: 'Bảo mật tài khoản',
                          subtitle: 'Mật khẩu và phiên đăng nhập',
                          onTap: () => _notAvailable(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const CustomerSectionHeader(title: 'Trợ giúp và pháp lý'),
                  const SizedBox(height: 12),
                  CustomerPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _AccountTile(
                          icon: Icons.headset_mic_outlined,
                          title: 'Trung tâm trợ giúp',
                          onTap: () => _notAvailable(context),
                        ),
                        _divider(context),
                        _AccountTile(
                          icon: Icons.description_outlined,
                          title: 'Điều khoản sử dụng',
                          onTap: () => _notAvailable(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => _logout(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.45),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Đăng xuất'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
    height: 1,
    indent: 68,
    color: Theme.of(context).colorScheme.outlineVariant,
  );

  void _showProfile(BuildContext context, Map<String, dynamic> customer) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Thông tin cá nhân',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              CustomerPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    _ProfileInfo(label: 'Họ và tên', value: customer['ho_ten']),
                    _ProfileInfo(
                      label: 'Số điện thoại',
                      value: customer['so_dien_thoai'],
                    ),
                    _ProfileInfo(label: 'Email', value: customer['email']),
                    _ProfileInfo(label: 'Địa chỉ', value: customer['dia_chi']),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _notAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tính năng này đang được hoàn thiện.')),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await CustomerAuthService().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.phone,
    required this.email,
  });

  final String name;
  final String phone;
  final String email;

  @override
  Widget build(BuildContext context) {
    final secondary = phone.isNotEmpty ? phone : email;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF143B38),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF4FAF9),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFD3E5E2)),
                  ),
                ],
                if (email.isNotEmpty && email != secondary) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF9EDBD3)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.primary10,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: AppColors.primary, size: 22),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _ProfileInfo extends StatelessWidget {
  const _ProfileInfo({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${value ?? 'Chưa cập nhật'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
