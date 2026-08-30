import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _trips = [];
  int? _warehouseId;
  bool _refreshing = false;
  RealtimeChannel? _warehouseChannel;
  Timer? _realtimeDebounce;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeWarehouseRealtime();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshWarehouseData(),
    );
  }

  void _subscribeWarehouseRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _warehouseChannel = Supabase.instance.client
        .channel('warehouse-overview-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chuyen_xe',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chuyen_xe_chang',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chi_tiet_chuyen_xe',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'don_hang',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .subscribe();
  }

  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(
      const Duration(milliseconds: 300),
      _refreshWarehouseData,
    );
  }

  Future<void> _refreshWarehouseData() async {
    final warehouseId = _warehouseId;
    if (!mounted || warehouseId == null || _refreshing || _loading) return;
    _refreshing = true;
    try {
      final values = await Future.wait([
        _service.overview(warehouseId),
        _service.orders(warehouseId),
        _service.trips(warehouseId),
      ]);
      if (!mounted || warehouseId != _warehouseId) return;
      setState(() {
        _overview = values[0] as Map<String, dynamic>;
        _orders = values[1] as List<Map<String, dynamic>>;
        _trips = values[2] as List<Map<String, dynamic>>;
        _error = null;
      });
    } on WarehouseManagerException {
      // Giữ dữ liệu hiện tại khi lần đồng bộ nền tạm thời thất bại.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _pollingTimer?.cancel();
    final channel = _warehouseChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final warehouses = await _service.managedWarehouses();
      final uniqueWarehouses = <int, Map<String, dynamic>>{};
      for (final warehouse in warehouses) {
        uniqueWarehouses[(warehouse['id'] as num).toInt()] = warehouse;
      }
      final distinctWarehouses = uniqueWarehouses.values.toList();
      if (distinctWarehouses.isEmpty) {
        throw const WarehouseManagerException(
          'Không có kho trong phạm vi quản lý',
        );
      }
      final availableIds = distinctWarehouses
          .map((item) => (item['id'] as num).toInt())
          .toSet();
      final warehouseId =
          _warehouseId != null && availableIds.contains(_warehouseId)
          ? _warehouseId!
          : (distinctWarehouses.first['id'] as num).toInt();
      final values = await Future.wait([
        _service.overview(warehouseId),
        _service.orders(warehouseId),
        _service.employees(warehouseId),
        _service.regions(),
        _service.trips(warehouseId),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = values[0] as Map<String, dynamic>;
        _orders = values[1] as List<Map<String, dynamic>>;
        _employees = values[2] as List<Map<String, dynamic>>;
        _warehouses = distinctWarehouses;
        _regions = values[3] as List<Map<String, dynamic>>;
        _trips = values[4] as List<Map<String, dynamic>>;
        _warehouseId = warehouseId;
      });
    } on WarehouseManagerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _overviewForDisplay() {
    final data = Map<String, dynamic>.from(_overview);
    final warehouseId = _warehouseId;
    if (warehouseId == null) return data;

    var arrivedPackages = 0;
    var incomingPackages = 0;
    for (final trip in _trips) {
      if ((trip['kho_den_id'] as num?)?.toInt() != warehouseId) continue;
      final packageCount = (trip['so_kien'] as num?)?.toInt() ?? 0;
      if (trip['trang_thai'] == 'DA_DEN') {
        arrivedPackages += packageCount;
      } else if (trip['trang_thai'] == 'DANG_DI') {
        incomingPackages += packageCount;
      }
    }

    final serverPending = (data['don_cho_xu_ly'] as num?)?.toInt() ?? 0;
    final serverIncoming = (data['dang_van_chuyen'] as num?)?.toInt() ?? 0;
    if (arrivedPackages > serverPending) {
      data['don_cho_xu_ly'] = arrivedPackages;
    }
    if (incomingPackages > serverIncoming) {
      data['dang_van_chuyen'] = incomingPackages;
    }
    return data;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (_tab) {
        0 => 'Tổng quan kho',
        1 => 'Đơn hàng tại kho',
        2 => 'Nhân sự kho',
        3 => 'Gán xe và chuyến xe',
        _ => 'Tài khoản quản lý',
      }),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
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
                    items: _warehouses
                        .map(
                          (warehouse) => DropdownMenuItem(
                            value: (warehouse['id'] as num).toInt(),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${warehouse['ten_kho']} • Cấp ${warehouse['cap_kho']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if ((warehouse['id'] as num).toInt() ==
                                    _warehouseId)
                                  const Icon(
                                    Icons.check_rounded,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
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
                    _Overview(data: _overviewForDisplay()),
                    _Orders(items: _orders),
                    _Employees(items: _employees),
                    _WarehouseTrips(items: _trips),
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
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Tổng quan',
        ),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'Đơn hàng',
        ),
        NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: 'Nhân sự',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_shipping_outlined),
          selectedIcon: Icon(Icons.local_shipping),
          label: 'Chuyến xe',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Tài khoản',
        ),
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
        : _tab == 3
        ? FloatingActionButton.extended(
            onPressed: _showCreateTrip,
            icon: const Icon(Icons.add_road),
            label: const Text('Gán xe'),
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
        parentProvince: '${_overview['tinh_thanh'] ?? ''}',
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
        regions: _regions,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _showCreateTrip() async {
    final warehouseId = _warehouseId!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final values = await Future.wait([
        _service.destinationWarehouses(warehouseId),
        _service.vehicles(warehouseId),
      ]);
      if (!mounted) return;
      Navigator.of(context).pop();
      final destinations = values[0];
      final vehicles = values[1];
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CreateTripDialog(
          service: _service,
          originWarehouseId: warehouseId,
          warehouses: destinations,
          vehicles: vehicles,
        ),
      );
      if (created == true) await _load();
    } on WarehouseManagerException catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warehouse, color: Colors.white, size: 34),
            const SizedBox(height: 10),
            Text(
              '${data['ten_kho'] ?? ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${data['ma_kho'] ?? ''} • ${data['dia_chi'] ?? ''}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
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
          _Metric(
            'Đang tại kho',
            data['don_tai_kho'],
            Icons.inventory_2_outlined,
            AppColors.primary,
          ),
          _Metric(
            'Chờ xử lý',
            data['don_cho_xu_ly'],
            Icons.pending_actions,
            AppColors.warning,
          ),
          _Metric(
            'Đang vận chuyển',
            data['dang_van_chuyen'],
            Icons.local_shipping_outlined,
            AppColors.info,
          ),
          _Metric(
            'Đã giao',
            data['da_giao'],
            Icons.check_circle_outline,
            AppColors.success,
          ),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            '${value ?? 0}',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          Text(label),
        ],
      ),
    ),
  );
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
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.inventory_2_outlined),
                ),
                title: Text(
                  '${item['ma_van_don']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${item['nguoi_gui_ten']} → ${item['nguoi_nhan_ten']}\n${item['trang_thai']}',
                ),
                isThreeLine: true,
                trailing: Text('${item['can_nang'] ?? 0} kg'),
              ),
            );
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
            final pickup = item['vai_tro'] == 'NHAN_VIEN_LAY_HANG';
            final delivery = item['vai_tro'] == 'NHAN_VIEN_GIAO_HANG';
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    manager
                        ? Icons.manage_accounts_outlined
                        : driver
                        ? Icons.local_shipping
                        : pickup
                        ? Icons.inventory_2_outlined
                        : delivery
                        ? Icons.delivery_dining_outlined
                        : Icons.badge_outlined,
                  ),
                ),
                title: Text(
                  '${item['ho_ten']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${manager
                      ? 'Quản lý kho cấp 2'
                      : driver
                      ? 'Tài xế xe tải'
                      : pickup
                      ? 'Nhân viên lấy hàng'
                      : delivery
                      ? 'Nhân viên giao hàng'
                      : 'Nhân viên kho'} • ${item['so_dien_thoai']}'
                  '${driver && item['bien_so_xe'] != null ? '\nXe: ${item['bien_so_xe']} • ${item['tai_trong']} kg' : ''}',
                ),
                isThreeLine: driver,
                trailing: Text('${item['trang_thai']}'),
              ),
            );
          },
        );
}

class _WarehouseTrips extends StatelessWidget {
  const _WarehouseTrips({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('Chưa có chuyến xe của kho'))
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final trip = items[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                title: Text(
                  '${trip['ma_chuyen']} • ${trip['bien_so_xe']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${trip['ten_kho_di']} → ${trip['ten_kho_den']}\nTài xế: ${trip['ten_tai_xe'] ?? 'Chưa có'} • ${trip['so_kien'] ?? 0} kiện',
                ),
                isThreeLine: true,
                trailing: Text('${trip['trang_thai']}'),
              ),
            );
          },
        );
}

class _CreateTripDialog extends StatefulWidget {
  const _CreateTripDialog({
    required this.service,
    required this.originWarehouseId,
    required this.warehouses,
    required this.vehicles,
  });
  final WarehouseManagerService service;
  final int originWarehouseId;
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> vehicles;
  @override
  State<_CreateTripDialog> createState() => _CreateTripDialogState();
}

class _CreateTripDialogState extends State<_CreateTripDialog> {
  int? _vehicleId;
  int? _destinationId;
  DateTime? _expectedAt;
  bool _saving = false;
  List<Map<String, dynamic>> get _availableVehicles => widget.vehicles
      .where((item) => item['trang_thai'] == 'SAN_SANG')
      .toList();
  List<Map<String, dynamic>> get _destinations => widget.warehouses
      .where((item) => (item['id'] as num).toInt() != widget.originWarehouseId)
      .toList();

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now(),
    );
    if (value != null) setState(() => _expectedAt = value);
  }

  Future<void> _submit() async {
    if (_vehicleId == null || _destinationId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hãy chọn xe và kho đến')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.createTrip(
        originWarehouseId: widget.originWarehouseId,
        destinationWarehouseId: _destinationId!,
        vehicleId: _vehicleId!,
        expectedAt: _expectedAt,
      );
      if (mounted) Navigator.pop(context, true);
    } on WarehouseManagerException catch (error) {
      if (mounted) {
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gán xe tạo chuyến'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _vehicleId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Xe sẵn sàng',
              prefixIcon: Icon(Icons.local_shipping_outlined),
            ),
            items: _availableVehicles
                .map(
                  (item) => DropdownMenuItem(
                    value: (item['id'] as num).toInt(),
                    child: Text(
                      '${item['bien_so_xe']} • ${item['ten_tai_xe']} • ${item['tai_trong']} kg',
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _vehicleId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _destinationId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Kho đến',
              prefixIcon: Icon(Icons.warehouse_outlined),
            ),
            items: _destinations
                .map(
                  (item) => DropdownMenuItem(
                    value: (item['id'] as num).toInt(),
                    child: Text(
                      '${item['ten_kho']} • Cấp ${item['cap_kho']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _destinationId = value),
          ),
          if (_destinations.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kho này chưa có tuyến hợp lệ. Nếu là kho cấp 2, hãy kiểm tra kho đã được gán đúng kho cấp 1 trực thuộc và kho cấp 1 đang hoạt động.',
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            leading: const Icon(Icons.event_outlined),
            title: Text(
              _expectedAt == null
                  ? 'Chọn ngày dự kiến (không bắt buộc)'
                  : 'Dự kiến: ${_expectedAt!.day}/${_expectedAt!.month}/${_expectedAt!.year}',
            ),
            onTap: _saving ? null : _pickDate,
          ),
          if (_availableVehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Kho chưa có xe ở trạng thái sẵn sàng'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed:
            _saving || _availableVehicles.isEmpty || _destinations.isEmpty
            ? null
            : _submit,
        child: Text(_saving ? 'Đang tạo...' : 'Tạo chuyến'),
      ),
    ],
  );
}

class _CreateWarehouseEmployeeDialog extends StatefulWidget {
  const _CreateWarehouseEmployeeDialog({
    required this.service,
    required this.warehouses,
    required this.initialWarehouseId,
    required this.regions,
  });
  final WarehouseManagerService service;
  final List<Map<String, dynamic>> warehouses;
  final int initialWarehouseId;
  final List<Map<String, dynamic>> regions;
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
  int? _regionId;
  late int _warehouseId;
  bool _saving = false;

  int get _selectedWarehouseLevel {
    final warehouse = widget.warehouses.firstWhere(
      (item) => (item['id'] as num).toInt() == _warehouseId,
    );
    return (warehouse['cap_kho'] as num).toInt();
  }

  bool get _isLevelOneManager =>
      widget.warehouses.any((item) => (item['cap_kho'] as num).toInt() == 1);

  bool get _isAreaEmployee =>
      _role == 'NHAN_VIEN_LAY_HANG' || _role == 'NHAN_VIEN_GIAO_HANG';

  void _syncWarehouseRegion() {
    final warehouse = widget.warehouses.firstWhere(
      (item) => (item['id'] as num).toInt() == _warehouseId,
    );
    final directId = (warehouse['khu_vuc_id'] as num?)?.toInt();
    if (directId != null) {
      _regionId = directId;
      return;
    }
    final address = '${warehouse['dia_chi'] ?? ''}'.toLowerCase();
    final match = widget.regions.where((region) {
      final ward = '${region['phuong_xa'] ?? ''}'.toLowerCase();
      final province = '${region['tinh_thanh'] ?? ''}'.toLowerCase();
      return ward.isNotEmpty &&
          province.isNotEmpty &&
          address.contains(ward) &&
          address.contains(province);
    }).firstOrNull;
    _regionId = (match?['id'] as num?)?.toInt();
  }

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'Họ và tên', Icons.person_outline),
              const SizedBox(height: 10),
              _field(_phone, 'Số điện thoại', Icons.phone_outlined),
              const SizedBox(height: 10),
              _field(_email, 'Email', Icons.email_outlined),
              const SizedBox(height: 10),
              _field(
                _password,
                'Mật khẩu ban đầu',
                Icons.lock_outline,
                obscure: true,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Vị trí',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: [
                  if (_isLevelOneManager && _selectedWarehouseLevel == 2)
                    const DropdownMenuItem(
                      value: 'QUAN_LY_KHO',
                      child: Text('Quản lý kho cấp 2'),
                    ),
                  const DropdownMenuItem(
                    value: 'NHAN_VIEN_KHO',
                    child: Text('Nhân viên kho'),
                  ),
                  const DropdownMenuItem(
                    value: 'VAN_CHUYEN',
                    child: Text('Tài xế xe tải'),
                  ),
                  const DropdownMenuItem(
                    value: 'NHAN_VIEN_LAY_HANG',
                    child: Text('Nhân viên lấy hàng'),
                  ),
                  const DropdownMenuItem(
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
              if (widget.warehouses.length > 1) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kho làm việc',
                    prefixIcon: Icon(Icons.warehouse_outlined),
                  ),
                  items: widget.warehouses
                      .map(
                        (warehouse) => DropdownMenuItem(
                          value: (warehouse['id'] as num).toInt(),
                          child: Text(
                            '${warehouse['ten_kho']} • Cấp ${warehouse['cap_kho']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _warehouseId = value!;
                          if (_role == 'QUAN_LY_KHO' &&
                              _selectedWarehouseLevel != 2) {
                            _role = 'NHAN_VIEN_KHO';
                          }
                          if (_isAreaEmployee) _syncWarehouseRegion();
                        }),
                ),
              ],
              if (_role == 'NHAN_VIEN_LAY_HANG' ||
                  _role == 'NHAN_VIEN_GIAO_HANG') ...[
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Phường/Xã phụ trách',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  child: Text(_automaticWarehouseWard),
                ),
              ],
              if (_role == 'VAN_CHUYEN') ...[
                const SizedBox(height: 10),
                _field(_plate, 'Biển số xe', Icons.local_shipping_outlined),
                const SizedBox(height: 10),
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
                    final number = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return _role == 'VAN_CHUYEN' &&
                            (number == null || number <= 0)
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
        child: Text(_saving ? 'Đang tạo...' : 'Tạo tài khoản'),
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
      if ((value ?? '').trim().isEmpty) return 'Không được để trống';
      if (obscure && (value ?? '').length < 6) return 'Tối thiểu 6 ký tự';
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
        warehouseId: _warehouseId,
        regionId: _regionId,
        licensePlate: _role == 'VAN_CHUYEN' ? _plate.text : null,
        payloadKg: _role == 'VAN_CHUYEN'
            ? double.tryParse(_payload.text.replaceAll(',', '.'))
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } on WarehouseManagerException catch (error) {
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
    final selected = widget.regions
        .where((item) => (item['id'] as num).toInt() == _regionId)
        .firstOrNull;
    if (selected != null) {
      return '${selected['phuong_xa']}, ${selected['tinh_thanh']}';
    }
    final warehouse = widget.warehouses.firstWhere(
      (item) => (item['id'] as num).toInt() == _warehouseId,
    );
    return '${warehouse['dia_chi'] ?? 'Kho chưa có khu vực'}';
  }
}

class _CreateManagedLevel2WarehouseDialog extends StatefulWidget {
  const _CreateManagedLevel2WarehouseDialog({
    required this.service,
    required this.parentName,
    required this.parentProvince,
  });
  final WarehouseManagerService service;
  final String parentName;
  final String parentProvince;
  @override
  State<_CreateManagedLevel2WarehouseDialog> createState() =>
      _CreateManagedLevel2WarehouseDialogState();
}

class _CreateManagedLevel2WarehouseDialogState
    extends State<_CreateManagedLevel2WarehouseDialog> {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.hub_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Kho cấp 1 quản lý'),
                subtitle: Text(widget.parentName),
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Tên kho cấp 2',
                  prefixIcon: Icon(Icons.warehouse_outlined),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Hãy nhập tên kho' : null,
              ),
              const SizedBox(height: 12),
              AddressInput(
                controller: _address,
                label: 'Địa chỉ kho',
                hint: 'Chọn tỉnh/thành, phường/xã và nhập số nhà',
                fixedProvince: widget.parentProvince.isEmpty
                    ? null
                    : widget.parentProvince,
                includeSubArea: false,
                validator: (_) => _province == null || _ward == null
                    ? 'Hãy chọn địa chỉ hành chính'
                    : null,
                onAddressChanged: () {
                  if (_province != null || _ward != null) {
                    setState(() {
                      _province = null;
                      _ward = null;
                    });
                  }
                },
                onAdministrativeAddressSelected: (selection) => setState(() {
                  _province = selection.province;
                  _ward = selection.ward;
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại (không bắt buộc)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
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
        onPressed: _saving ? null : _submit,
        icon: const Icon(Icons.add_business),
        label: Text(_saving ? 'Đang tạo...' : 'Tạo kho'),
      ),
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

class _Account extends StatelessWidget {
  const _Account({required this.data, required this.onLogout});
  final Map<String, dynamic> data;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const CircleAvatar(
          radius: 42,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.manage_accounts, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 12),
        Text(
          '${data['quan_ly_ten'] ?? ''}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Quản lý kho'),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.warehouse_outlined),
          title: Text('${data['ten_kho'] ?? ''}'),
          subtitle: Text('${data['dia_chi'] ?? ''}'),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ),
      ],
    ),
  );
}
