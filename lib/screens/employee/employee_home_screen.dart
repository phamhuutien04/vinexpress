import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/warehouse_employee_service.dart';
import '../auth/login_screen.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  final _service = WarehouseEmployeeService();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([_service.overview(), _service.assignedOrders()]);
      if (!mounted) return;
      setState(() {
        _overview = values[0] as Map<String, dynamic>;
        _orders = values[1] as List<Map<String, dynamic>>;
      });
    } on WarehouseEmployeeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            0 => 'Tổng quan công việc',
            1 => 'Đơn hàng tại kho',
            _ => 'Tài khoản',
          }),
          actions: [
            if (_tab != 2)
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, retry: _load)
                : IndexedStack(
                    index: _tab,
                    children: [
                      _Dashboard(data: _overview, orders: _orders),
                      _OrderList(orders: _orders),
                      _Account(data: _overview, onLogout: _logout),
                    ],
                  ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Tổng quan'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Đơn hàng'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Tài khoản'),
          ],
        ),
      );

  Future<void> _logout() async {
    await CustomerAuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.data, required this.orders});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const CircleAvatar(radius: 30, backgroundColor: Colors.white, child: Icon(Icons.warehouse, size: 34, color: AppColors.primary)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${data['ho_ten'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${data['ten_kho'] ?? ''} • Kho cấp ${data['cap_kho'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text('${data['ma_kho'] ?? ''}', style: const TextStyle(color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Công việc hôm nay', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 1 ? 3.2 : 1.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _Metric(value: data['don_tai_kho'], label: 'Đơn đang tại kho', icon: Icons.inventory_2_outlined, color: AppColors.info),
              _Metric(value: data['cho_xu_ly'], label: 'Đơn chờ xử lý', icon: Icons.pending_actions, color: AppColors.warning),
              _Metric(value: data['da_xu_ly_hom_nay'], label: 'Đã xử lý hôm nay', icon: Icons.task_alt, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: Text('Cần xử lý gần đây', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text('${orders.length} đơn', style: TextStyle(color: colorScheme.primary)),
          ]),
          const SizedBox(height: 10),
          if (orders.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(children: [Icon(Icons.inbox_outlined, size: 42, color: colorScheme.outline), const SizedBox(height: 8), const Text('Hiện không có đơn cần xử lý')])) )
          else
            ...orders.take(5).map((order) => _OrderCard(order: order)),
        ],
      );
    });
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, required this.icon, required this.color});
  final dynamic value;
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${value ?? 0}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ])),
          ]),
        ),
      );
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});
  final List<Map<String, dynamic>> orders;
  @override
  Widget build(BuildContext context) => orders.isEmpty
      ? const Center(child: Text('Không có đơn hàng tại kho'))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (_, index) => _OrderCard(order: orders[index]),
        );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
          title: Text('${order['ma_van_don']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${order['nguoi_gui_ten']} → ${order['nguoi_nhan_ten']}\n${_status(order['trang_thai'])}'),
          isThreeLine: true,
          trailing: Text('${order['can_nang'] ?? 0} kg'),
        ),
      );

  String _status(dynamic value) => switch ('$value') {
        'DA_LAY_HANG' => 'Đã lấy hàng',
        'DANG_VAN_CHUYEN' => 'Đang vận chuyển',
        'DEN_KHO_TRUNG_CHUYEN' => 'Đến kho trung chuyển',
        'DEN_KHO_DICH' => 'Đến kho đích',
        _ => '$value',
      };
}

class _Account extends StatelessWidget {
  const _Account({required this.data, required this.onLogout});
  final Map<String, dynamic> data;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(radius: 44, backgroundColor: AppColors.primary, child: Icon(Icons.badge_outlined, color: Colors.white, size: 44)),
          const SizedBox(height: 14),
          Text('${data['ho_ten'] ?? ''}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Text('Nhân viên kho', textAlign: TextAlign.center),
          const SizedBox(height: 22),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.warehouse_outlined), title: Text('${data['ten_kho'] ?? ''}'), subtitle: Text('${data['dia_chi'] ?? ''}')),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.phone_outlined), title: Text('${data['so_dien_thoai'] ?? ''}')),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.email_outlined), title: Text('${data['email'] ?? ''}')),
          ])),
          const SizedBox(height: 22),
          OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout), label: const Text('Đăng xuất')),
        ],
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 48), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Thử lại'))])));
}
