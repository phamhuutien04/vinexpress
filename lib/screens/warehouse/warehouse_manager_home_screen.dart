import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/warehouse_manager_service.dart';
import '../../widgets/address_input.dart';
import '../auth/login_screen.dart';

class WarehouseManagerHomeScreen extends StatefulWidget {
  const WarehouseManagerHomeScreen({super.key});

  @override
  State<WarehouseManagerHomeScreen> createState() =>
      _WarehouseManagerHomeScreenState();
}

class _WarehouseManagerHomeScreenState
    extends State<WarehouseManagerHomeScreen> {
  final _service = WarehouseManagerService();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _warehouses = [];
  int? _warehouseId;

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
      final warehouses = await _service.managedWarehouses();
      if (warehouses.isEmpty) throw const WarehouseManagerException('Không có kho trong phạm vi quản lý');
      final availableIds = warehouses.map((item) => (item['id'] as num).toInt()).toSet();
      final warehouseId = _warehouseId != null && availableIds.contains(_warehouseId)
          ? _warehouseId!
          : (warehouses.first['id'] as num).toInt();
      final values = await Future.wait([
        _service.overview(warehouseId),
        _service.orders(warehouseId),
        _service.employees(warehouseId),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = values[0] as Map<String, dynamic>;
        _orders = values[1] as List<Map<String, dynamic>>;
        _employees = values[2] as List<Map<String, dynamic>>;
        _warehouses = warehouses;
        _warehouseId = warehouseId;
      });
    } on WarehouseManagerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            0 => 'Tổng quan kho',
            1 => 'Đơn hàng tại kho',
            2 => 'Nhân sự kho',
            _ => 'Tài khoản quản lý',
          }),
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : Column(
                    children: [
                      if (_warehouses.length > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: DropdownButtonFormField<int>(
                            initialValue: _warehouseId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kho đang quản lý',
                              prefixIcon: Icon(Icons.account_tree_outlined),
                            ),
                            items: _warehouses.map((warehouse) => DropdownMenuItem(
                              value: (warehouse['id'] as num).toInt(),
                              child: Text(
                                '${warehouse['ten_kho']} • Cấp ${warehouse['cap_kho']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )).toList(),
                            onChanged: (value) {
                              if (value == null || value == _warehouseId) return;
                              setState(() => _warehouseId = value);
                              _load();
                            },
                          ),
                        ),
                      Expanded(
                        child: IndexedStack(
                          index: _tab,
                          children: [
                            _Overview(data: _overview),
                            _Orders(items: _orders),
                            _Employees(items: _employees),
                            _Account(data: _overview, onLogout: _logout),
                          ],
                        ),
                      ),
                    ],
                  ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Tổng quan'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Đơn hàng'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Nhân sự'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Tài khoản'),
          ],
        ),
        floatingActionButton: _tab == 0 && _overview['cap_kho'] == 1
            ? FloatingActionButton.extended(
                onPressed: _showCreateLevel2Warehouse,
                icon: const Icon(Icons.add_business),
                label: const Text('Thêm kho cấp 2'),
              )
            : _tab == 2
            ? FloatingActionButton.extended(
                onPressed: _showCreateEmployee,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Thêm nhân viên'),
              )
            : null,
      );

  Future<void> _showCreateLevel2Warehouse() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateManagedLevel2WarehouseDialog(
        service: _service,
        parentName: '${_overview['ten_kho'] ?? ''}',
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _showCreateEmployee() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateWarehouseEmployeeDialog(
        service: _service,
        warehouses: _warehouses,
        initialWarehouseId: _warehouseId!,
      ),
    );
    if (created == true) await _load();
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
  const _Overview({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warehouse, color: Colors.white, size: 34),
              const SizedBox(height: 10),
              Text('${data['ten_kho'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
              Text('${data['ma_kho'] ?? ''} • ${data['dia_chi'] ?? ''}', style: const TextStyle(color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _Metric('Đang tại kho', data['don_tai_kho'], Icons.inventory_2_outlined, AppColors.primary),
              _Metric('Chờ xử lý', data['don_cho_xu_ly'], Icons.pending_actions, AppColors.warning),
              _Metric('Đang vận chuyển', data['dang_van_chuyen'], Icons.local_shipping_outlined, AppColors.info),
              _Metric('Đã giao', data['da_giao'], Icons.check_circle_outline, AppColors.success),
            ],
          ),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final dynamic value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color), const SizedBox(height: 8), Text('${value ?? 0}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), Text(label)])));
}

class _Orders extends StatelessWidget {
  const _Orders({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('Kho chưa có đơn hàng'))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final item = items[index];
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
              title: Text('${item['ma_van_don']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${item['nguoi_gui_ten']} → ${item['nguoi_nhan_ten']}\n${item['trang_thai']}'),
              isThreeLine: true,
              trailing: Text('${item['can_nang'] ?? 0} kg'),
            ));
          },
        );
}

class _Employees extends StatelessWidget {
  const _Employees({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('Kho chưa có nhân viên'))
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final item = items[index];
            final driver = item['vai_tro'] == 'VAN_CHUYEN';
            final manager = item['vai_tro'] == 'QUAN_LY_KHO';
            return Card(child: ListTile(
              leading: CircleAvatar(child: Icon(
                manager
                    ? Icons.manage_accounts_outlined
                    : driver
                    ? Icons.local_shipping
                    : Icons.badge_outlined,
              )),
              title: Text('${item['ho_ten']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${manager ? 'Quản lý kho cấp 2' : driver ? 'Tài xế xe tải' : 'Nhân viên kho'} • ${item['so_dien_thoai']}'
                '${driver && item['bien_so_xe'] != null ? '\nXe: ${item['bien_so_xe']} • ${item['tai_trong']} kg' : ''}',
              ),
              isThreeLine: driver,
              trailing: Text('${item['trang_thai']}'),
            ));
          },
        );
}

class _CreateWarehouseEmployeeDialog extends StatefulWidget {
  const _CreateWarehouseEmployeeDialog({
    required this.service,
    required this.warehouses,
    required this.initialWarehouseId,
  });
  final WarehouseManagerService service;
  final List<Map<String, dynamic>> warehouses;
  final int initialWarehouseId;
  @override
  State<_CreateWarehouseEmployeeDialog> createState() =>
      _CreateWarehouseEmployeeDialogState();
}

class _CreateWarehouseEmployeeDialogState
    extends State<_CreateWarehouseEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _plate = TextEditingController();
  final _payload = TextEditingController();
  String _role = 'NHAN_VIEN_KHO';
  late int _warehouseId;
  bool _saving = false;

  int get _selectedWarehouseLevel {
    final warehouse = widget.warehouses.firstWhere(
      (item) => (item['id'] as num).toInt() == _warehouseId,
    );
    return (warehouse['cap_kho'] as num).toInt();
  }

  bool get _isLevelOneManager => widget.warehouses.any(
        (item) => (item['cap_kho'] as num).toInt() == 1,
      );

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.initialWarehouseId;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _plate.dispose();
    _payload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Thêm nhân sự vào kho'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _field(_name, 'Họ và tên', Icons.person_outline),
                const SizedBox(height: 10),
                _field(_phone, 'Số điện thoại', Icons.phone_outlined),
                const SizedBox(height: 10),
                _field(_email, 'Email', Icons.email_outlined),
                const SizedBox(height: 10),
                _field(_password, 'Mật khẩu ban đầu', Icons.lock_outline, obscure: true),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Vị trí', prefixIcon: Icon(Icons.badge_outlined)),
                  items: [
                    if (_isLevelOneManager && _selectedWarehouseLevel == 2)
                      const DropdownMenuItem(value: 'QUAN_LY_KHO', child: Text('Quản lý kho cấp 2')),
                    const DropdownMenuItem(value: 'NHAN_VIEN_KHO', child: Text('Nhân viên kho')),
                    const DropdownMenuItem(value: 'VAN_CHUYEN', child: Text('Tài xế xe tải')),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _role = value!),
                ),
                if (widget.warehouses.length > 1) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _warehouseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kho làm việc',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                    items: widget.warehouses.map((warehouse) => DropdownMenuItem(
                      value: (warehouse['id'] as num).toInt(),
                      child: Text('${warehouse['ten_kho']} • Cấp ${warehouse['cap_kho']}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: _saving ? null : (value) => setState(() {
                      _warehouseId = value!;
                      if (_role == 'QUAN_LY_KHO' && _selectedWarehouseLevel != 2) {
                        _role = 'NHAN_VIEN_KHO';
                      }
                    }),
                  ),
                ],
                if (_role == 'VAN_CHUYEN') ...[
                  const SizedBox(height: 10),
                  _field(_plate, 'Biển số xe', Icons.local_shipping_outlined),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _payload,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tải trọng (kg)', prefixIcon: Icon(Icons.scale_outlined)),
                    validator: (value) {
                      final number = double.tryParse((value ?? '').replaceAll(',', '.'));
                      return _role == 'VAN_CHUYEN' && (number == null || number <= 0)
                          ? 'Tải trọng phải lớn hơn 0'
                          : null;
                    },
                  ),
                ],
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Đang tạo...' : 'Tạo tài khoản')),
        ],
      );

  TextFormField _field(TextEditingController controller, String label, IconData icon, {bool obscure = false}) => TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: (value) {
          if ((value ?? '').trim().isEmpty) return 'Không được để trống';
          if (obscure && (value ?? '').length < 6) return 'Tối thiểu 6 ký tự';
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
        warehouseId: _warehouseId,
        licensePlate: _role == 'VAN_CHUYEN' ? _plate.text : null,
        payloadKg: _role == 'VAN_CHUYEN'
            ? double.tryParse(_payload.text.replaceAll(',', '.'))
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } on WarehouseManagerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: AppColors.error),
      );
      setState(() => _saving = false);
    }
  }
}

class _CreateManagedLevel2WarehouseDialog extends StatefulWidget {
  const _CreateManagedLevel2WarehouseDialog({required this.service, required this.parentName});
  final WarehouseManagerService service;
  final String parentName;
  @override
  State<_CreateManagedLevel2WarehouseDialog> createState() => _CreateManagedLevel2WarehouseDialogState();
}

class _CreateManagedLevel2WarehouseDialogState extends State<_CreateManagedLevel2WarehouseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  String? _province;
  String? _ward;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Thêm kho cấp 2 trực thuộc'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading: const Icon(Icons.hub_outlined, color: AppColors.primary),
                  title: const Text('Kho cấp 1 quản lý'),
                  subtitle: Text(widget.parentName),
                ),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Tên kho cấp 2', prefixIcon: Icon(Icons.warehouse_outlined)),
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Hãy nhập tên kho' : null,
                ),
                const SizedBox(height: 12),
                AddressInput(
                  controller: _address,
                  label: 'Địa chỉ kho',
                  hint: 'Chọn tỉnh/thành, phường/xã và nhập số nhà',
                  validator: (_) => _province == null || _ward == null ? 'Hãy chọn địa chỉ hành chính' : null,
                  onAddressChanged: () {
                    if (_province != null || _ward != null) setState(() { _province = null; _ward = null; });
                  },
                  onAdministrativeAddressSelected: (selection) => setState(() {
                    _province = selection.province;
                    _ward = selection.ward;
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Số điện thoại (không bắt buộc)', prefixIcon: Icon(Icons.phone_outlined)),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.add_business), label: Text(_saving ? 'Đang tạo...' : 'Tạo kho')),
        ],
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.service.createLevel2Warehouse(
        name: _name.text,
        address: _address.text,
        province: _province!,
        ward: _ward!,
        phone: _phone.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on WarehouseManagerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message), backgroundColor: AppColors.error));
      setState(() => _saving = false);
    }
  }
}

class _Account extends StatelessWidget {
  const _Account({required this.data, required this.onLogout});
  final Map<String, dynamic> data;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const CircleAvatar(radius: 42, backgroundColor: AppColors.primary, child: Icon(Icons.manage_accounts, color: Colors.white, size: 42)),
          const SizedBox(height: 12),
          Text('${data['quan_ly_ten'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
          const Text('Quản lý kho'),
          const SizedBox(height: 20),
          ListTile(leading: const Icon(Icons.warehouse_outlined), title: Text('${data['ten_kho'] ?? ''}'), subtitle: Text('${data['dia_chi'] ?? ''}')),
          const Spacer(),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout), label: const Text('Đăng xuất'))),
        ]),
      );
}
