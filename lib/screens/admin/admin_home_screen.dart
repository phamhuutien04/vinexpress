import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/admin_service.dart';
import '../../services/customer_auth_service.dart';
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

  static const _titles = ['Tổng quan', 'Nhân viên', 'Khách hàng', 'Đơn hàng'];
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
      ]);
      if (!mounted) return;
      setState(() {
        _overview = result[0] as Map<String, dynamic>;
        _employees = result[1] as List<Map<String, dynamic>>;
        _customers = result[2] as List<Map<String, dynamic>>;
        _orders = result[3] as List<Map<String, dynamic>>;
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
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Admin • ${_titles[_selected]}'),
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
          floatingActionButton: _selected == 1
              ? FloatingActionButton.extended(
                  onPressed: _showCreateEmployee,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Tạo nhân viên'),
                )
              : null,
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
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
                    child: Icon(Icons.admin_panel_settings, color: Colors.white),
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
      1 => _EmployeeList(
          employees: _employees,
          onAction: _updateEmployee,
        ),
      2 => _CustomerList(customers: _customers),
      _ => _OrderList(orders: _orders),
    };
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
      builder: (_) => _CreateEmployeeDialog(service: _service),
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
    final cards = [
      ('Nhân viên', data['tong_nhan_vien'], Icons.badge, AppColors.primary),
      ('Chờ duyệt', data['nhan_vien_cho_duyet'], Icons.pending_actions, Colors.orange),
      ('Khách hàng', data['tong_khach_hang'], Icons.groups, Colors.blue),
      ('Tổng đơn', data['tong_don_hang'], Icons.receipt_long, Colors.purple),
      ('Chờ lấy', data['don_cho_lay'], Icons.inventory_2, Colors.orange),
      ('Đang giao', data['don_dang_giao'], Icons.local_shipping, Colors.blue),
      ('Đã giao', data['don_da_giao'], Icons.check_circle, Colors.green),
      ('Doanh thu', _money(data['tong_doanh_thu_van_chuyen']), Icons.payments, Colors.teal),
    ];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisExtent: 145,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: cards.length,
        itemBuilder: (_, index) {
          final item = cards[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.$3, color: item.$4, size: 30),
                  const Spacer(),
                  Text('${item.$2 ?? 0}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                  Text(item.$1, style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
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
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(child: Text('${item['ho_ten']}'.substring(0, 1).toUpperCase())),
              title: Text('${item['ho_ten']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${_role(item['vai_tro'])} • ${item['email']}\n${item['so_dien_thoai']} • ${item['trang_thai_duyet']}'),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (value) => onAction(item, value),
                itemBuilder: (_) => [
                  if (pending) const PopupMenuItem(value: 'approve', child: Text('Duyệt tài khoản')),
                  if (pending) const PopupMenuItem(value: 'reject', child: Text('Từ chối')),
                  PopupMenuItem(value: locked ? 'unlock' : 'lock', child: Text(locked ? 'Mở khóa' : 'Khóa tài khoản')),
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
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text('${item['ho_ten']}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
              title: Text('${item['ma_van_don']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${item['khach_hang_ten']} → ${item['nguoi_nhan_ten']}\n${item['trang_thai']} • ${item['shipper_ten'] ?? 'Chưa có shipper'}'),
              isThreeLine: true,
              trailing: Text(_money(item['phi_van_chuyen']), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          );
        },
      );
}

class _CreateEmployeeDialog extends StatefulWidget {
  const _CreateEmployeeDialog({required this.service});
  final AdminService service;

  @override
  State<_CreateEmployeeDialog> createState() => _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends State<_CreateEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'SHIPPER';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
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
                  _field(_password, 'Mật khẩu ban đầu', Icons.lock_outline, obscure: true),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Vai trò', prefixIcon: Icon(Icons.badge_outlined)),
                    items: const [
                      DropdownMenuItem(value: 'SHIPPER', child: Text('Shipper')),
                      DropdownMenuItem(value: 'VAN_CHUYEN', child: Text('Nhân viên vận chuyển')),
                      DropdownMenuItem(value: 'NHAN_VIEN_KHO', child: Text('Nhân viên kho')),
                      DropdownMenuItem(value: 'QUAN_LY_KHO', child: Text('Quản lý kho')),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _role = value!),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Tạo tài khoản'),
          ),
        ],
      );

  TextFormField _field(TextEditingController controller, String label, IconData icon, {bool obscure = false}) => TextFormField(
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
    setState(() => _saving = true);
    try {
      await widget.service.createEmployee(
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        password: _password.text,
        role: _role,
      );
      if (mounted) Navigator.pop(context, true);
    } on AdminServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: AppColors.error),
      );
      setState(() => _saving = false);
    }
  }
}

String _role(dynamic value) => switch ('$value') {
      'ADMIN' => 'Quản trị viên',
      'QUAN_LY_KHO' => 'Quản lý kho',
      'NHAN_VIEN_KHO' => 'Nhân viên kho',
      'VAN_CHUYEN' => 'Vận chuyển',
      _ => 'Shipper',
    };

String _money(dynamic value) {
  final amount = (value as num?)?.round() ?? 0;
  return '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')}đ';
}
