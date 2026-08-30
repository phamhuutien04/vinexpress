import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/admin_service.dart';
import '../../services/customer_auth_service.dart';
import '../../widgets/address_input.dart';
import '../auth/login_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _service = AdminService();
  int _selected = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _walletRequests = [];

  static const _titles = [
    'Tổng quan',
    'Nhân viên',
    'Khách hàng',
    'Đơn hàng',
    'Kho hàng',
    'Duyệt ví',
  ];
  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Tổng quan',
    ),
    NavigationDestination(
      icon: Icon(Icons.badge_outlined),
      selectedIcon: Icon(Icons.badge),
      label: 'Nhân viên',
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: 'Khách hàng',
    ),
    NavigationDestination(
      icon: Icon(Icons.local_shipping_outlined),
      selectedIcon: Icon(Icons.local_shipping),
      label: 'Đơn hàng',
    ),
    NavigationDestination(
      icon: Icon(Icons.warehouse_outlined),
      selectedIcon: Icon(Icons.warehouse),
      label: 'Kho hàng',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet),
      label: 'Duyệt ví',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _service.getOverview(),
        _service.getEmployees(),
        _service.getCustomers(),
        _service.getOrders(),
        _service.getWarehouses(),
        _service.getRegions(),
        _service.getWalletRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = result[0] as Map<String, dynamic>;
        _employees = result[1] as List<Map<String, dynamic>>;
        _customers = result[2] as List<Map<String, dynamic>>;
        _orders = result[3] as List<Map<String, dynamic>>;
        _warehouses = result[4] as List<Map<String, dynamic>>;
        _regions = result[5] as List<Map<String, dynamic>>;
        _walletRequests = result[6] as List<Map<String, dynamic>>;
      });
    } on AdminServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final scaffold = Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              _selected == 0 ? 'Quản trị VinExpress' : _titles[_selected],
            ),
            actions: [
              IconButton(
                tooltip: 'Làm mới',
                onPressed: _loading ? null : _loadAll,
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'logout') _logout();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
                ],
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          body: _body(),
          floatingActionButton: switch (_selected) {
            1 => FloatingActionButton.extended(
              onPressed: _showCreateEmployee,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Tạo nhân viên'),
            ),
            4 => FloatingActionButton.extended(
              onPressed: _showCreateWarehouse,
              icon: const Icon(Icons.add_business),
              label: const Text('Thêm kho'),
            ),
            _ => null,
          },
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  selectedIndex: _selected,
                  onDestinationSelected: (value) {
                    setState(() => _selected = value);
                  },
                  destinations: _destinations,
                ),
        );
        if (!desktop) return scaffold;
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selected,
                extended: constraints.maxWidth >= 1180,
                onDestinationSelected: (value) {
                  setState(() => _selected = value);
                },
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: AppColors.primary,
                    child: Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                    ),
                  ),
                ),
                destinations: _destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: scaffold),
            ],
          ),
        );
      },
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 58),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    return switch (_selected) {
      0 => _AdminOverview(data: _overview, onRefresh: _loadAll),
      1 => _EmployeeList(employees: _employees, onAction: _updateEmployee),
      2 => _CustomerList(customers: _customers),
      3 => _OrderList(orders: _orders),
      4 => _WarehouseList(warehouses: _warehouses, employees: _employees),
      _ => _WalletRequestList(
        requests: _walletRequests,
        onProcess: _processWalletRequest,
        onRefresh: _loadAll,
      ),
    };
  }

  Future<void> _processWalletRequest(
    Map<String, dynamic> request,
    String action,
  ) async {
    final requestId = (request['id'] as num).toInt();
    String? reason;
    if (action == 'TU_CHOI') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Từ chối yêu cầu'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Lý do từ chối',
              hintText: 'Nhập lý do để người dùng biết',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Xác nhận từ chối'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    } else {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            request['loai'] == 'NAP_TIEN' ? 'Duyệt nạp tiền' : 'Duyệt rút tiền',
          ),
          content: Text(
            'Xác nhận duyệt ${_money(request['so_tien'])} cho '
            '${request['chu_vi']}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Duyệt yêu cầu'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }

    try {
      await _service.processWalletRequest(
        requestId: requestId,
        action: action,
        rejectionReason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'DUYET'
                ? 'Đã duyệt yêu cầu #$requestId'
                : 'Đã từ chối yêu cầu #$requestId',
          ),
        ),
      );
      await _loadAll();
    } on AdminServiceException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _updateEmployee(
    Map<String, dynamic> employee,
    String action,
  ) async {
    try {
      switch (action) {
        case 'approve':
          await _service.updateEmployee(
            employeeId: (employee['id'] as num).toInt(),
            approvalStatus: 'DA_DUYET',
          );
          break;
        case 'reject':
          await _service.updateEmployee(
            employeeId: (employee['id'] as num).toInt(),
            approvalStatus: 'TU_CHOI',
          );
          break;
        case 'lock':
          await _service.updateEmployee(
            employeeId: (employee['id'] as num).toInt(),
            accountStatus: 'TAM_KHOA',
          );
          break;
        case 'unlock':
          await _service.updateEmployee(
            employeeId: (employee['id'] as num).toInt(),
            accountStatus: 'HOAT_DONG',
          );
          break;
      }
      await _loadAll();
    } on AdminServiceException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _showCreateEmployee() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateEmployeeDialog(
        service: _service,
        warehouses: _warehouses,
        regions: _regions,
      ),
    );
    if (created == true) await _loadAll();
  }

  Future<void> _showCreateWarehouse() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CreateWarehouseDialog(service: _service, warehouses: _warehouses),
    );
    if (created == true) await _loadAll();
  }

  Future<void> _logout() async {
    await CustomerAuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}

class _AdminOverview extends StatelessWidget {
  const _AdminOverview({required this.data, required this.onRefresh});
  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final name = CustomerAuthService.currentEmployee?['ho_ten'] ?? 'Admin';
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Colors.white,
                    size: 31,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Xin chào,',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        '$name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Quản trị viên hệ thống',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle(
            title: 'Tổng quan hệ thống',
            subtitle: 'Dữ liệu được cập nhật theo thời gian thực',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 4 : 2;
              final ratio = constraints.maxWidth >= 760 ? 1.75 : 1.48;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: ratio,
                children: [
                  _SummaryCard(
                    label: 'Nhân viên',
                    value: '${data['tong_nhan_vien'] ?? 0}',
                    icon: Icons.badge_outlined,
                    color: AppColors.primary,
                  ),
                  _SummaryCard(
                    label: 'Chờ duyệt',
                    value: '${data['nhan_vien_cho_duyet'] ?? 0}',
                    icon: Icons.pending_actions_outlined,
                    color: Colors.orange,
                  ),
                  _SummaryCard(
                    label: 'Khách hàng',
                    value: '${data['tong_khach_hang'] ?? 0}',
                    icon: Icons.groups_outlined,
                    color: Colors.blue,
                  ),
                  _SummaryCard(
                    label: 'Tổng đơn hàng',
                    value: '${data['tong_don_hang'] ?? 0}',
                    icon: Icons.receipt_long_outlined,
                    color: Colors.purple,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Tình trạng vận hành',
            subtitle: 'Theo dõi tiến độ giao hàng',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  _OrderMetric(
                    value: data['don_cho_lay'],
                    label: 'Chờ lấy',
                    color: Colors.orange,
                  ),
                  _OrderMetric(
                    value: data['don_dang_giao'],
                    label: 'Đang giao',
                    color: Colors.blue,
                  ),
                  _OrderMetric(
                    value: data['don_da_giao'],
                    label: 'Đã giao',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: .25),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.payments_outlined, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Doanh thu vận chuyển',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _money(data['tong_doanh_thu_van_chuyen']),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrderMetric extends StatelessWidget {
  const _OrderMetric({
    required this.value,
    required this.label,
    required this.color,
  });
  final dynamic value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '${value ?? 0}',
          style: TextStyle(
            color: color,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _EmployeeList extends StatelessWidget {
  const _EmployeeList({required this.employees, required this.onAction});
  final List<Map<String, dynamic>> employees;
  final void Function(Map<String, dynamic>, String) onAction;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    itemCount: employees.length,
    itemBuilder: (_, index) {
      final item = employees[index];
      final pending = item['trang_thai_duyet'] == 'CHO_DUYET';
      final locked = item['trang_thai'] != 'HOAT_DONG';
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: CircleAvatar(
            child: Text('${item['ho_ten']}'.substring(0, 1).toUpperCase()),
          ),
          title: Text(
            '${item['ho_ten']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${_role(item['vai_tro'])} • ${item['email']}\n'
            '${item['so_dien_thoai']} • ${item['trang_thai_duyet']}'
            '${item['ten_kho'] == null ? '' : '\nKho: ${item['ten_kho']}'}',
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (value) => onAction(item, value),
            itemBuilder: (_) => [
              if (pending)
                const PopupMenuItem(
                  value: 'approve',
                  child: Text('Duyệt tài khoản'),
                ),
              if (pending)
                const PopupMenuItem(value: 'reject', child: Text('Từ chối')),
              PopupMenuItem(
                value: locked ? 'unlock' : 'lock',
                child: Text(locked ? 'Mở khóa' : 'Khóa tài khoản'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CustomerList extends StatelessWidget {
  const _CustomerList({required this.customers});
  final List<Map<String, dynamic>> customers;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: customers.length,
    itemBuilder: (_, index) {
      final item = customers[index];
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(
            '${item['ho_ten']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${item['email']}\n${item['so_dien_thoai']}'),
          trailing: Text('${item['tong_don']} đơn'),
        ),
      );
    },
  );
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: orders.length,
    itemBuilder: (_, index) {
      final item = orders[index];
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.local_shipping_outlined),
          ),
          title: Text(
            '${item['ma_van_don']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${item['khach_hang_ten']} → ${item['nguoi_nhan_ten']}\n${item['trang_thai']} • ${item['shipper_ten'] ?? 'Chưa có shipper'}',
          ),
          isThreeLine: true,
          trailing: Text(
            _money(item['phi_van_chuyen']),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    },
  );
}

class _WalletRequestList extends StatefulWidget {
  const _WalletRequestList({
    required this.requests,
    required this.onProcess,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> requests;
  final Future<void> Function(Map<String, dynamic>, String) onProcess;
  final Future<void> Function() onRefresh;

  @override
  State<_WalletRequestList> createState() => _WalletRequestListState();
}

class _WalletRequestListState extends State<_WalletRequestList> {
  String? _status = 'CHO_DUYET';
  String? _type;

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests.where((item) {
      final statusMatches = _status == null || item['trang_thai'] == _status;
      final typeMatches = _type == null || item['loai'] == _type;
      return statusMatches && typeMatches;
    }).toList();
    final pending = widget.requests
        .where((item) => item['trang_thai'] == 'CHO_DUYET')
        .length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.price_check_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Kiểm soát giao dịch ví',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$pending yêu cầu đang chờ xử lý',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Trạng thái',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _filterChip('Chờ duyệt', 'CHO_DUYET', true),
                      _filterChip('Đã duyệt', 'DA_DUYET', true),
                      _filterChip('Từ chối', 'TU_CHOI', true),
                      _filterChip('Tất cả', null, true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _filterChip('Nạp tiền', 'NAP_TIEN', false),
                      _filterChip('Rút tiền', 'RUT_TIEN', false),
                      _filterChip('Cả hai', null, false),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (requests.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _WalletEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              sliver: SliverList.builder(
                itemCount: requests.length,
                itemBuilder: (_, index) => _WalletRequestCard(
                  request: requests[index],
                  onProcess: widget.onProcess,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value, bool statusFilter) {
    final selected = statusFilter ? _status == value : _type == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        if (statusFilter) {
          _status = value;
        } else {
          _type = value;
        }
      }),
    );
  }
}

class _WalletRequestCard extends StatelessWidget {
  const _WalletRequestCard({required this.request, required this.onProcess});

  final Map<String, dynamic> request;
  final Future<void> Function(Map<String, dynamic>, String) onProcess;

  @override
  Widget build(BuildContext context) {
    final isTopUp = request['loai'] == 'NAP_TIEN';
    final isPending = request['trang_thai'] == 'CHO_DUYET';
    final statusColor = switch (request['trang_thai']) {
      'DA_DUYET' => Colors.green,
      'TU_CHOI' => AppColors.error,
      _ => Colors.orange,
    };

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: (isTopUp ? Colors.green : Colors.blue)
                      .withValues(alpha: .12),
                  child: Icon(
                    isTopUp
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: isTopUp ? Colors.green : Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isTopUp ? 'Nạp tiền vào ví' : 'Rút tiền khỏi ví',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '#${request['id']} • ${_dateTime(request['ngay_tao'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  _money(request['so_tien']),
                  style: TextStyle(
                    color: isTopUp ? Colors.green.shade700 : Colors.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _WalletInfoLine(
              icon: Icons.person_outline,
              label:
                  '${request['chu_vi']} • ${_ownerType(request['loai_chu_vi'])}',
            ),
            if ('${request['so_dien_thoai'] ?? ''}'.isNotEmpty)
              _WalletInfoLine(
                icon: Icons.phone_outlined,
                label: '${request['so_dien_thoai']}',
              ),
            if (isTopUp)
              _WalletInfoLine(
                icon: Icons.payments_outlined,
                label: 'Phương thức: ${_paymentMethod(request['phuong_thuc'])}',
              )
            else ...[
              _WalletInfoLine(
                icon: Icons.account_balance_outlined,
                label: '${request['ngan_hang']} • ${request['so_tai_khoan']}',
              ),
              _WalletInfoLine(
                icon: Icons.badge_outlined,
                label: 'Chủ tài khoản: ${request['chu_tai_khoan']}',
              ),
            ],
            _WalletInfoLine(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Số dư hiện tại: ${_money(request['so_du_hien_tai'])}',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _walletStatus(request['trang_thai']),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (isPending) ...[
                  OutlinedButton(
                    onPressed: () => onProcess(request, 'TU_CHOI'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    child: const Text('Từ chối'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => onProcess(request, 'DUYET'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Duyệt'),
                  ),
                ],
              ],
            ),
            if ('${request['ly_do_tu_choi'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Lý do: ${request['ly_do_tu_choi']}',
                style: const TextStyle(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletInfoLine extends StatelessWidget {
  const _WalletInfoLine({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

class _WalletEmptyState extends StatelessWidget {
  const _WalletEmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt_rounded,
            size: 58,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          const Text(
            'Không có yêu cầu phù hợp',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Các yêu cầu nạp và rút tiền sẽ xuất hiện tại đây.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _WarehouseList extends StatelessWidget {
  const _WarehouseList({required this.warehouses, required this.employees});
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> employees;

  void _showDetails(BuildContext context, Map<String, dynamic> warehouse) {
    final warehouseId = (warehouse['id'] as num).toInt();
    final staff = employees
        .where((item) => (item['kho_hang_id'] as num?)?.toInt() == warehouseId)
        .toList();
    final managers = staff
        .where((item) => item['vai_tro'] == 'QUAN_LY_KHO')
        .toList();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${warehouse['ten_kho']}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.warehouse_outlined),
                  ),
                  title: Text(
                    '${warehouse['ma_kho']} • Kho cấp ${warehouse['cap_kho']}',
                  ),
                  subtitle: Text('${warehouse['dia_chi']}'),
                ),
                const Divider(),
                Text(
                  'Quản lý kho',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (managers.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.person_off_outlined),
                      title: Text('Kho chưa có quản lý'),
                    ),
                  )
                else
                  ...managers.map(
                    (manager) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            Icons.manage_accounts,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          '${manager['ho_ten']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${manager['email'] ?? 'Chưa có email'}\n'
                          '${manager['so_dien_thoai']} • ${manager['trang_thai_duyet']}',
                        ),
                        isThreeLine: true,
                        trailing: Text('${manager['trang_thai']}'),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('Tổng nhân sự thuộc kho: ${staff.length}'),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (warehouses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warehouse_outlined, size: 58),
            SizedBox(height: 10),
            Text('Chưa có kho hàng'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: warehouses.length,
      itemBuilder: (_, index) {
        final item = warehouses[index];
        final level = (item['cap_kho'] as num?)?.toInt() ?? 1;
        final color = level == 1 ? AppColors.primary : Colors.blue;
        return Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showDetails(context, item),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.warehouse_outlined, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item['ten_kho']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Cấp $level',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text('${item['ma_kho']} • ${item['tinh_thanh']}'),
                        Text(
                          '${item['dia_chi']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (level == 2) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Trực thuộc: ${item['ten_kho_trung_tam'] ?? 'Chưa xác định'}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateWarehouseDialog extends StatefulWidget {
  const _CreateWarehouseDialog({
    required this.service,
    required this.warehouses,
  });
  final AdminService service;
  final List<Map<String, dynamic>> warehouses;

  @override
  State<_CreateWarehouseDialog> createState() => _CreateWarehouseDialogState();
}

class _CreateWarehouseDialogState extends State<_CreateWarehouseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  int _level = 1;
  String? _province;
  String? _ward;
  int? _parentId;
  bool _saving = false;

  List<Map<String, dynamic>> get _availableParents {
    return widget.warehouses.where((item) {
      return item['cap_kho'] == 1 &&
          (_province == null || item['tinh_thanh'] == _province);
    }).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thêm kho hàng'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.hub_outlined),
                    label: Text('Kho cấp 1'),
                  ),
                  ButtonSegment(
                    value: 2,
                    icon: Icon(Icons.account_tree_outlined),
                    label: Text('Kho cấp 2'),
                  ),
                ],
                selected: {_level},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _level = value.first;
                        _parentId = null;
                      }),
              ),
              const SizedBox(height: 16),
              _warehouseField(_name, 'Tên kho', Icons.warehouse_outlined),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mã kho được hệ thống tạo tự động khi lưu.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              AddressInput(
                controller: _address,
                label: 'Địa chỉ kho',
                hint: 'Chọn Tỉnh/Thành, Phường/Xã và nhập số nhà',
                validator: (_) => _province == null || _ward == null
                    ? 'Hãy chọn địa chỉ bằng nút bên dưới'
                    : null,
                onAddressChanged: () {
                  if (_province != null || _ward != null) {
                    setState(() {
                      _province = null;
                      _ward = null;
                      _parentId = null;
                    });
                  }
                },
                onAdministrativeAddressSelected: (selection) {
                  setState(() {
                    _province = selection.province;
                    _ward = selection.ward;
                    _parentId = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              _warehouseField(
                _phone,
                'Số điện thoại (không bắt buộc)',
                Icons.phone_outlined,
                required: false,
              ),
              if (_level == 2) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _parentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kho cấp 1 trực thuộc',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: _availableParents.map((item) {
                    return DropdownMenuItem(
                      value: (item['id'] as num).toInt(),
                      child: Text(
                        '${item['ten_kho']} (${item['ma_kho']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  validator: (value) => _level == 2 && value == null
                      ? 'Hãy chọn kho cấp 1'
                      : null,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _parentId = value),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _create,
        icon: _saving
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_business),
        label: const Text('Tạo kho'),
      ),
    ],
  );

  TextFormField _warehouseField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: required
          ? (value) =>
                (value?.trim().isEmpty ?? true) ? 'Không được để trống' : null
          : null,
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.service.createWarehouse(
        name: _name.text,
        address: _address.text,
        province: _province!,
        ward: _ward!,
        level: _level,
        phone: _phone.text,
        parentWarehouseId: _parentId,
      );
      if (mounted) Navigator.pop(context, true);
    } on AdminServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _saving = false);
    }
  }
}

class _CreateEmployeeDialog extends StatefulWidget {
  const _CreateEmployeeDialog({
    required this.service,
    required this.warehouses,
    required this.regions,
  });
  final AdminService service;
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> regions;

  @override
  State<_CreateEmployeeDialog> createState() => _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends State<_CreateEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _licensePlate = TextEditingController();
  final _payload = TextEditingController();
  String _role = 'SHIPPER';
  int? _warehouseId;
  int? _regionId;
  bool _saving = false;

  bool get _isAreaEmployee =>
      _role == 'NHAN_VIEN_LAY_HANG' || _role == 'NHAN_VIEN_GIAO_HANG';

  void _syncWarehouseRegion() {
    if (_warehouseId == null) {
      _regionId = null;
      return;
    }
    final warehouse = widget.warehouses.firstWhere(
      (item) => (item['id'] as num).toInt() == _warehouseId,
    );
    _regionId = (warehouse['khu_vuc_id'] as num?)?.toInt();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _licensePlate.dispose();
    _payload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tạo tài khoản nhân viên'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'Họ và tên', Icons.person_outline),
              const SizedBox(height: 12),
              _field(_phone, 'Số điện thoại', Icons.phone_outlined),
              const SizedBox(height: 12),
              _field(_email, 'Email', Icons.email_outlined),
              const SizedBox(height: 12),
              _field(
                _password,
                'Mật khẩu ban đầu',
                Icons.lock_outline,
                obscure: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Vai trò',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'SHIPPER', child: Text('Shipper')),
                  DropdownMenuItem(
                    value: 'VAN_CHUYEN',
                    child: Text('Tài xế xe tải'),
                  ),
                  DropdownMenuItem(
                    value: 'NHAN_VIEN_KHO',
                    child: Text('Nhân viên kho'),
                  ),
                  DropdownMenuItem(
                    value: 'QUAN_LY_KHO',
                    child: Text('Quản lý kho'),
                  ),
                  DropdownMenuItem(
                    value: 'NHAN_VIEN_LAY_HANG',
                    child: Text('Nhân viên lấy hàng'),
                  ),
                  DropdownMenuItem(
                    value: 'NHAN_VIEN_GIAO_HANG',
                    child: Text('Nhân viên giao hàng'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _role = value!;
                        if (_isAreaEmployee) _syncWarehouseRegion();
                      }),
              ),
              if (_role == 'QUAN_LY_KHO' ||
                  _role == 'NHAN_VIEN_KHO' ||
                  _role == 'NHAN_VIEN_LAY_HANG' ||
                  _role == 'NHAN_VIEN_GIAO_HANG') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kho làm việc',
                    prefixIcon: Icon(Icons.warehouse_outlined),
                  ),
                  items: widget.warehouses.map((warehouse) {
                    return DropdownMenuItem(
                      value: (warehouse['id'] as num).toInt(),
                      child: Text(
                        '${warehouse['ten_kho']} (${warehouse['ma_kho']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  validator: (value) =>
                      (_role == 'QUAN_LY_KHO' ||
                              _role == 'NHAN_VIEN_KHO' ||
                              _role == 'NHAN_VIEN_LAY_HANG' ||
                              _role == 'NHAN_VIEN_GIAO_HANG') &&
                          value == null
                      ? 'Hãy chọn kho làm việc'
                      : null,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _warehouseId = value;
                          if (_isAreaEmployee) _syncWarehouseRegion();
                        }),
                ),
              ],
              if (_role == 'NHAN_VIEN_LAY_HANG' ||
                  _role == 'NHAN_VIEN_GIAO_HANG') ...[
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Phường/Xã phụ trách',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  child: Text(_automaticWarehouseWard),
                ),
              ],
              if (_role == 'VAN_CHUYEN') ...[
                const SizedBox(height: 12),
                _field(
                  _licensePlate,
                  'Biển số xe tải',
                  Icons.local_shipping_outlined,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _payload,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tải trọng (kg)',
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                  validator: (value) {
                    if (_role != 'VAN_CHUYEN') return null;
                    final number = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return number == null || number <= 0
                        ? 'Tải trọng phải lớn hơn 0'
                        : null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Tạo tài khoản'),
      ),
    ],
  );

  TextFormField _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
  }) => TextFormField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    validator: (value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return 'Không được để trống';
      if (obscure && text.length < 6) return 'Tối thiểu 6 ký tự';
      return null;
    },
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isAreaEmployee && _regionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy chọn phường/xã phụ trách')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.createEmployee(
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        warehouseId:
            _role == 'QUAN_LY_KHO' ||
                _role == 'NHAN_VIEN_KHO' ||
                _role == 'NHAN_VIEN_LAY_HANG' ||
                _role == 'NHAN_VIEN_GIAO_HANG'
            ? _warehouseId
            : null,
        regionId: _regionId,
        licensePlate: _role == 'VAN_CHUYEN' ? _licensePlate.text : null,
        payloadKg: _role == 'VAN_CHUYEN'
            ? double.tryParse(_payload.text.replaceAll(',', '.'))
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } on AdminServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _saving = false);
    }
  }

  String get _automaticWarehouseWard {
    if (_warehouseId == null) return 'Hãy chọn kho làm việc';
    final warehouse = widget.warehouses.firstWhere(
      (item) => (item['id'] as num).toInt() == _warehouseId,
    );
    return '${warehouse['phuong_xa'] ?? ''}, ${warehouse['tinh_thanh'] ?? ''}';
  }
}

String _role(dynamic value) => switch ('$value') {
  'ADMIN' => 'Quản trị viên',
  'QUAN_LY_KHO' => 'Quản lý kho',
  'NHAN_VIEN_KHO' => 'Nhân viên kho',
  'VAN_CHUYEN' => 'Vận chuyển',
  'NHAN_VIEN_LAY_HANG' => 'Nhân viên lấy hàng',
  'NHAN_VIEN_GIAO_HANG' => 'Nhân viên giao hàng',
  _ => 'Shipper',
};

String _money(dynamic value) {
  final amount = (value as num?)?.round() ?? 0;
  return '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')}đ';
}

String _walletStatus(dynamic value) => switch ('$value') {
  'DA_DUYET' => 'Đã duyệt',
  'TU_CHOI' => 'Đã từ chối',
  _ => 'Chờ duyệt',
};

String _ownerType(dynamic value) => switch ('$value') {
  'KHACH_HANG' => 'Khách hàng',
  'NHAN_VIEN_LAY_HANG' => 'Nhân viên lấy hàng',
  'NHAN_VIEN_GIAO_HANG' => 'Nhân viên giao hàng',
  'VAN_CHUYEN' => 'Nhân viên vận chuyển',
  'QUAN_LY_KHO' => 'Quản lý kho',
  'NHAN_VIEN_KHO' => 'Nhân viên kho',
  _ => 'Nhân viên',
};

String _paymentMethod(dynamic value) => switch ('$value') {
  'CHUYEN_KHOAN' => 'Chuyển khoản',
  'TIEN_MAT' => 'Tiền mặt',
  _ => '$value',
};

String _dateTime(dynamic value) {
  final parsed = DateTime.tryParse('$value')?.toLocal();
  if (parsed == null) return 'Không rõ thời gian';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(parsed.hour)}:${two(parsed.minute)} '
      '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
}
