import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../auth/login_screen.dart';
import '../shipper/nearby_orders_screen.dart';
import '../shipper/shipper_order_history_screen.dart';
import '../shipper/shipper_wallet_screen.dart';
import '../wallet/bank_account_screen.dart';

class DeliveryHomeScreen extends StatefulWidget {
  const DeliveryHomeScreen({super.key});

  @override
  State<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends State<DeliveryHomeScreen> {
  int _tab = 0;

  String get _name =>
      CustomerAuthService.currentEmployee?['ho_ten'] as String? ?? 'Shipper';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(switch (_tab) {
          0 => 'Nhận đơn gần bạn',
          1 => 'Ví shipper',
          2 => 'Lịch sử giao hàng',
          _ => 'Tài khoản shipper',
        }),
        actions: _tab == 0
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Chip(
                    avatar: const Icon(
                      Icons.delivery_dining_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    label: Text(_name),
                  ),
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const NearbyOrdersScreen(embedded: true),
          const ShipperWalletScreen(),
          const ShipperOrderHistoryScreen(),
          _ProfilePage(name: _name, onLogout: _logout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me_rounded),
            label: 'Đơn gần bạn',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Ví',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Lịch sử',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await CustomerAuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.name, required this.onLogout});
  final String name;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final employee = CustomerAuthService.currentEmployee ?? const {};
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 28),
          const CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primary,
            child: Icon(
              Icons.delivery_dining_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            employee['vai_tro'] == 'VAN_CHUYEN'
                ? 'Nhân viên vận chuyển'
                : 'Shipper',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row(
                    Icons.phone_outlined,
                    '${employee['so_dien_thoai'] ?? ''}',
                  ),
                  const Divider(height: 24),
                  _row(Icons.email_outlined, '${employee['email'] ?? ''}'),
                  const Divider(height: 24),
                  _row(Icons.verified_outlined, 'Đã duyệt hoạt động'),
                ],
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BankAccountScreen()),
            ),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Tài khoản ngân hàng'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}
