import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
      final values = await Future.wait([
        _service.overview(),
        _service.assignedOrders(),
      ]);
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
        2 => 'Quét hàng theo chuyến',
        _ => 'Tài khoản',
      }),
      actions: [
        if (_tab != 3)
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
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
              _TripScanner(service: _service, onChanged: _load),
              _Account(data: _overview, onLogout: _logout),
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
          icon: Icon(Icons.qr_code_scanner),
          selectedIcon: Icon(Icons.qr_code_scanner),
          label: 'Quét hàng',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Tài khoản',
        ),
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

class _TripScanner extends StatefulWidget {
  const _TripScanner({required this.service, required this.onChanged});
  final WarehouseEmployeeService service;
  final Future<void> Function() onChanged;
  @override
  State<_TripScanner> createState() => _TripScannerState();
}

class _TripScannerState extends State<_TripScanner> {
  final _vehicleController = TextEditingController();
  int? _tripId;
  String _action = 'XEP_LEN_XE';
  bool _saving = false;
  bool _searching = false;
  bool _searched = false;
  Map<String, dynamic>? _vehicle;
  List<Map<String, dynamic>> _trips = [];

  @override
  void dispose() {
    _vehicleController.dispose();
    super.dispose();
  }

  void _clearVehicleResult() {
    if (!_searched && _vehicle == null && _trips.isEmpty) return;
    setState(() {
      _searched = false;
      _vehicle = null;
      _trips = [];
      _tripId = null;
    });
  }

  Future<void> _findVehicle({bool notifyWhenEmpty = true}) async {
    final keyword = _vehicleController.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập ID xe hoặc biển số xe')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searched = false;
      _vehicle = null;
      _trips = [];
      _tripId = null;
    });
    try {
      final result = await widget.service.findTripsByVehicle(keyword);
      if (!mounted) return;
      final trips = List<Map<String, dynamic>>.from(
        (result['chuyen_xe'] as List?) ?? const [],
      );
      setState(() {
        _searched = true;
        _vehicle = result['xe'] == null
            ? null
            : Map<String, dynamic>.from(result['xe'] as Map);
        _trips = trips;
        if (trips.length == 1) {
          _tripId = (trips.first['id'] as num).toInt();
        }
      });
      if (notifyWhenEmpty && trips.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Xe tồn tại nhưng chưa có chuyến phù hợp tại kho này',
            ),
          ),
        );
      }
    } on WarehouseEmployeeException catch (error) {
      if (!mounted) return;
      setState(() => _searched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _receiveAtWarehouse() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _WarehouseQrScanner()),
    );
    if (code == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.service.receiveParcel(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã nhập kiện hàng vào kho'),
          backgroundColor: AppColors.success,
        ),
      );
      await widget.onChanged();
    } on WarehouseEmployeeException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan() async {
    if (_tripId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hãy chọn chuyến xe trước')));
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _WarehouseQrScanner()),
    );
    if (code == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await widget.service.scanParcel(
        tripId: _tripId!,
        code: code,
        action: _action,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'DA_XEP_HANG'
                ? 'Đã xếp kiện lên xe'
                : 'Đã nhập kiện vào kho',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      await _findVehicle(notifyWhenEmpty: false);
    } on WarehouseEmployeeException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasTrips = _trips.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            32,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WarehouseReceivePanel(
                      saving: _saving,
                      onScan: _receiveAtWarehouse,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Xử lý theo chuyến xe',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Chọn thao tác và chuyến xe trước khi quét kiện',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary10,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _searched
                                ? '${_trips.length} chuyến'
                                : 'Chưa chọn xe',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, actionConstraints) {
                              final narrow = actionConstraints.maxWidth < 560;
                              final tiles = [
                                _WarehouseActionTile(
                                  icon: Icons.move_to_inbox_rounded,
                                  title: 'Xếp lên xe',
                                  subtitle: 'Quét kiện rời khỏi kho',
                                  selected: _action == 'XEP_LEN_XE',
                                  onTap: _saving
                                      ? null
                                      : () => setState(
                                          () => _action = 'XEP_LEN_XE',
                                        ),
                                ),
                                _WarehouseActionTile(
                                  icon: Icons.inventory_2_rounded,
                                  title: 'Dỡ xe nhập kho',
                                  subtitle: 'Quét kiện vừa đến kho',
                                  selected: _action == 'NHAP_KHO',
                                  onTap: _saving
                                      ? null
                                      : () => setState(
                                          () => _action = 'NHAP_KHO',
                                        ),
                                ),
                              ];
                              if (narrow) {
                                return Column(
                                  children: [
                                    tiles.first,
                                    const SizedBox(height: 10),
                                    tiles.last,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: tiles.first),
                                  const SizedBox(width: 12),
                                  Expanded(child: tiles.last),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, searchConstraints) {
                              final compact = searchConstraints.maxWidth < 560;
                              final input = TextField(
                                controller: _vehicleController,
                                enabled: !_searching && !_saving,
                                textInputAction: TextInputAction.search,
                                autocorrect: false,
                                textCapitalization:
                                    TextCapitalization.characters,
                                onChanged: (_) => _clearVehicleResult(),
                                onSubmitted: (_) => _findVehicle(),
                                decoration: const InputDecoration(
                                  labelText: 'ID xe hoặc biển số xe',
                                  hintText: 'Ví dụ: 29C346028 hoặc 12',
                                  prefixIcon: Icon(
                                    Icons.directions_car_outlined,
                                  ),
                                ),
                              );
                              final button = SizedBox(
                                height: 56,
                                child: FilledButton.icon(
                                  onPressed: _searching || _saving
                                      ? null
                                      : () => _findVehicle(),
                                  icon: _searching
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.search_rounded),
                                  label: Text(
                                    _searching
                                        ? 'Đang kiểm tra'
                                        : 'Kiểm tra xe',
                                  ),
                                ),
                              );
                              if (compact) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    input,
                                    const SizedBox(height: 10),
                                    button,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: input),
                                  const SizedBox(width: 10),
                                  SizedBox(width: 180, child: button),
                                ],
                              );
                            },
                          ),
                          if (_vehicle != null) ...[
                            const SizedBox(height: 12),
                            _VehicleLookupResult(vehicle: _vehicle!),
                          ],
                          if (hasTrips) ...[
                            const SizedBox(height: 14),
                            DropdownButtonFormField<int>(
                              key: ValueKey(
                                '${_vehicle?['id']}-$_tripId-${_trips.length}',
                              ),
                              initialValue: _tripId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Chuyến của xe tại kho',
                                hintText: 'Chọn chuyến xe để xử lý',
                                prefixIcon: Icon(Icons.local_shipping_outlined),
                              ),
                              items: _trips
                                  .map(
                                    (trip) => DropdownMenuItem(
                                      value: (trip['id'] as num).toInt(),
                                      child: Text(
                                        '${trip['ma_chuyen']} • ${trip['bien_so_xe']} • ${trip['ten_kho_di']} → ${trip['ten_kho_den']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _tripId = value),
                            ),
                          ],
                          const SizedBox(height: 14),
                          if (hasTrips)
                            SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _scan,
                                icon: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.qr_code_scanner_rounded),
                                label: Text(
                                  _saving
                                      ? 'Đang xử lý...'
                                      : 'Quét mã kiện hàng',
                                ),
                              ),
                            )
                          else
                            _WarehouseVehiclePrompt(
                              searched: _searched,
                              vehicleFound: _vehicle != null,
                              onRetry: () => _findVehicle(),
                            ),
                        ],
                      ),
                    ),
                    if (hasTrips) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Chuyến xe được gán',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._trips.map((trip) => _AssignedTripCard(trip: trip)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WarehouseReceivePanel extends StatelessWidget {
  const _WarehouseReceivePanel({required this.saving, required this.onScan});

  final bool saving;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: AppColors.primaryGradient,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryShadow,
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final information = Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nhập kiện vào kho',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Nhận kiện từ nhân viên lấy hàng bằng QR hoặc Code 128',
                    style: TextStyle(color: Colors.white, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        );
        final button = SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: saving ? null : onScan,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              disabledBackgroundColor: Colors.white54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text(
              'Quét mã nhập kho',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [information, const SizedBox(height: 18), button],
          );
        }
        return Row(
          children: [
            Expanded(child: information),
            const SizedBox(width: 24),
            SizedBox(width: 210, child: button),
          ],
        );
      },
    ),
  );
}

class _WarehouseActionTile extends StatelessWidget {
  const _WarehouseActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppColors.primary10 : colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : colors.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.primary : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleLookupResult extends StatelessWidget {
  const _VehicleLookupResult({required this.vehicle});

  final Map<String, dynamic> vehicle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary10,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${vehicle['bien_so_xe']}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID xe: ${vehicle['id']}'
                  '${vehicle['ten_tai_xe'] == null ? '' : ' • Tài xế: ${vehicle['ten_tai_xe']}'}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Text(
            'Đã xác minh',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseVehiclePrompt extends StatelessWidget {
  const _WarehouseVehiclePrompt({
    required this.searched,
    required this.vehicleFound,
    required this.onRetry,
  });

  final bool searched;
  final bool vehicleFound;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              searched ? Icons.route_outlined : Icons.search_rounded,
              size: 30,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            searched && vehicleFound
                ? 'Xe chưa có chuyến phù hợp'
                : searched
                ? 'Không tìm thấy xe'
                : 'Nhập xe để tìm chuyến',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            searched && vehicleFound
                ? 'Xe đã được xác minh nhưng không có chuyến đi hoặc đến kho này.'
                : searched
                ? 'Kiểm tra lại ID xe hoặc biển số rồi thử lại.'
                : 'Nhập đúng ID xe hoặc biển số xe. Hệ thống sẽ kiểm tra rồi mới hiển thị chuyến được gán.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          if (searched) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Kiểm tra lại'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignedTripCard extends StatelessWidget {
  const _AssignedTripCard({required this.trip});

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary10,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trip['ma_chuyen']}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${trip['ten_kho_di']} → ${trip['ten_kho_den']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${trip['so_kien']} kiện',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${trip['bien_so_xe']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarehouseQrScanner extends StatefulWidget {
  const _WarehouseQrScanner();
  @override
  State<_WarehouseQrScanner> createState() => _WarehouseQrScannerState();
}

class _WarehouseQrScannerState extends State<_WarehouseQrScanner> {
  bool _handled = false;
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét mã kiện hàng')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_handled || capture.barcodes.isEmpty) return;
            final value = capture.barcodes.first.rawValue;
            if (value == null || value.trim().isEmpty) return;
            _handled = true;
            Navigator.pop(context, value.trim());
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 4),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.data, required this.orders});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.warehouse,
                      size: 34,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data['ho_ten'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${data['ten_kho'] ?? ''} • Kho cấp ${data['cap_kho'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${data['ma_kho'] ?? ''}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Công việc hôm nay',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: columns == 1 ? 3.2 : 1.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _Metric(
                  value: data['don_tai_kho'],
                  label: 'Đơn đang tại kho',
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.info,
                ),
                _Metric(
                  value: data['cho_xu_ly'],
                  label: 'Đơn chờ xử lý',
                  icon: Icons.pending_actions,
                  color: AppColors.warning,
                ),
                _Metric(
                  value: data['da_xu_ly_hom_nay'],
                  label: 'Đã xử lý hôm nay',
                  icon: Icons.task_alt,
                  color: AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cần xử lý gần đây',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${orders.length} đơn',
                  style: TextStyle(color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (orders.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 42,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      const Text('Hiện không có đơn cần xử lý'),
                    ],
                  ),
                ),
              )
            else
              ...orders.take(5).map((order) => _OrderCard(order: order)),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final dynamic value;
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${value ?? 0}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
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
      title: Text(
        '${order['ma_van_don']}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${order['nguoi_gui_ten']} → ${order['nguoi_nhan_ten']}\n${_status(order['trang_thai'])}',
      ),
      isThreeLine: true,
      trailing: Text('${order['can_nang'] ?? 0} kg'),
    ),
  );

  String _status(dynamic value) => switch ('$value') {
    'DA_LAY_HANG' => 'Nhân viên đang mang về kho',
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
      const CircleAvatar(
        radius: 44,
        backgroundColor: AppColors.primary,
        child: Icon(Icons.badge_outlined, color: Colors.white, size: 44),
      ),
      const SizedBox(height: 14),
      Text(
        '${data['ho_ten'] ?? ''}',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const Text('Nhân viên kho', textAlign: TextAlign.center),
      const SizedBox(height: 22),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.warehouse_outlined),
              title: Text('${data['ten_kho'] ?? ''}'),
              subtitle: Text('${data['dia_chi'] ?? ''}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text('${data['so_dien_thoai'] ?? ''}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text('${data['email'] ?? ''}'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout),
        label: const Text('Đăng xuất'),
      ),
    ],
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}
