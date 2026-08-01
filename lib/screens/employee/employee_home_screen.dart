import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../auth/login_screen.dart';

/// Home page for warehouse and office employees.
/// Delivery staff use [DeliveryHomeScreen] after signing in.
class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  int _tab = 0;

  Map<String, dynamic> get _employee =>
      CustomerAuthService.currentEmployee ?? <String, dynamic>{};

  @override
  Widget build(BuildContext context) {
    final name = _employee['ho_ten'] as String? ?? 'Nhân viên';
    final role = _employee['vai_tro'] as String? ?? 'NHAN_VIEN_KHO';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_tab == 0 ? 'Trang nhân viên' : 'Tài khoản')),
      body: IndexedStack(
        index: _tab,
        children: [
          _Overview(name: name, role: role),
          _Account(name: name, role: role, onLogout: _logout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Tổng quan',
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

class _Overview extends StatelessWidget {
  const _Overview({required this.name, required this.role});

  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ca làm việc hôm nay', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_roleLabel(role), style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Tiến độ hôm nay', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(child: _Metric(value: '08', label: 'Đơn cần xử lý', icon: Icons.assignment_outlined)),
            SizedBox(width: 12),
            Expanded(child: _Metric(value: '05', label: 'Đã hoàn thành', icon: Icons.check_circle_outline)),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Công việc', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
            title: Text('Đơn hàng chờ xử lý'),
            subtitle: Text('Danh sách đơn sẽ được cập nhật khi có phân công.'),
          ),
        ),
      ],
    );
  }

  String _roleLabel(String role) => switch (role) {
        'QUAN_LY_KHO' => 'Quản lý kho',
        'NHAN_VIEN_KHO' => 'Nhân viên kho',
        'ADMIN' => 'Quản trị viên',
        _ => 'Nhân viên',
      };
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _Account extends StatelessWidget {
  const _Account({required this.name, required this.role, required this.onLogout});

  final String name;
  final String role;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            const CircleAvatar(radius: 42, child: Icon(Icons.person_rounded, size: 46)),
            const SizedBox(height: 16),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(role, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const Spacer(),
            OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout_rounded), label: const Text('Đăng xuất')),
          ],
        ),
      );
}
