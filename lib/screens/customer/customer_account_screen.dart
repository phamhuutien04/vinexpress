import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../auth/login_screen.dart';
import '../wallet/bank_account_screen.dart';

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.person, color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (phone.isNotEmpty) Text(phone),
                        if (email.isNotEmpty) Text(email),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Thông tin tài khoản',
            children: [
              _AccountTile(
                icon: Icons.person_outline_rounded,
                title: 'Thông tin cá nhân',
                subtitle: 'Tên, số điện thoại và địa chỉ',
                onTap: () => _showProfile(context, customer),
              ),
              _AccountTile(
                icon: Icons.account_balance_outlined,
                title: 'Liên kết tài khoản ngân hàng',
                subtitle: 'Dùng để nhận tiền khi rút ví',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BankAccountScreen()),
                ),
              ),
              _AccountTile(
                icon: Icons.lock_outline_rounded,
                title: 'Bảo mật tài khoản',
                subtitle: 'Mật khẩu và phiên đăng nhập',
                onTap: () => _notAvailable(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Hỗ trợ',
            children: [
              _AccountTile(
                icon: Icons.help_outline_rounded,
                title: 'Trung tâm trợ giúp',
                onTap: () => _notAvailable(context),
              ),
              _AccountTile(
                icon: Icons.description_outlined,
                title: 'Điều khoản sử dụng',
                onTap: () => _notAvailable(context),
              ),
            ],
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  void _showProfile(BuildContext context, Map<String, dynamic> customer) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Thông tin cá nhân',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _info('Họ và tên', customer['ho_ten']),
              _info('Số điện thoại', customer['so_dien_thoai']),
              _info('Email', customer['email']),
              _info('Địa chỉ', customer['dia_chi']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 105, child: Text(label)),
          Expanded(
            child: Text(
              '${value ?? 'Chưa cập nhật'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
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
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
