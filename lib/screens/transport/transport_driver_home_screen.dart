import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/transport_driver_service.dart';
import '../auth/login_screen.dart';
import 'transport_driver_navigation_screen.dart';

class TransportDriverHomeScreen extends StatefulWidget {
  const TransportDriverHomeScreen({super.key});

  @override
  State<TransportDriverHomeScreen> createState() =>
      _TransportDriverHomeScreenState();
}

class _TransportDriverHomeScreenState extends State<TransportDriverHomeScreen> {
  final _service = TransportDriverService();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _trips = [];

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
      final result = await Future.wait([
        _service.getProfile(),
        _service.getTrips(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = result[0] as Map<String, dynamic>;
        _trips = result[1] as List<Map<String, dynamic>>;
      });
    } on TransportDriverException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_profile['ho_ten'] ?? 'Tài xế xe tải'}';
    final activeTrips = _trips
        .where(
          (trip) => !['DA_HOAN_THANH', 'DA_HUY'].contains(trip['trang_thai']),
        )
        .toList();
    final historyTrips = _trips
        .where(
          (trip) => ['DA_HOAN_THANH', 'DA_HUY'].contains(trip['trang_thai']),
        )
        .toList();
    const titles = <String>[
      'Lộ trình vận chuyển',
      'Lịch sử chuyến',
      'Tài khoản tài xế',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab != 2)
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Làm mới dữ liệu',
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _loading
          ? const _TripsLoadingView()
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : IndexedStack(
              index: _tab,
              children: [
                _TripsView(
                  profile: _profile,
                  trips: activeTrips,
                  onUpdate: _updateTrip,
                ),
                _TripHistoryView(trips: historyTrips),
                _DriverAccount(
                  profile: _profile,
                  name: name,
                  onLogout: _logout,
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Chuyến xe',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.manage_history_rounded),
            label: 'Lịch sử',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }

  Future<void> _updateTrip(int id, String status) async {
    try {
      await _service.updateTrip(id, status);
      await _load();
    } on TransportDriverException catch (error) {
      if (!mounted) return;
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

class _TripsView extends StatelessWidget {
  const _TripsView({
    required this.profile,
    required this.trips,
    required this.onUpdate,
  });

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> trips;
  final Future<void> Function(int, String) onUpdate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          18,
          horizontalPadding,
          32,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DriverSummary(profile: profile, trips: trips),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Chuyến được phân công',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${trips.length} chuyến',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (profile['xe_id'] == null)
                    const _EmptyState(
                      icon: Icons.no_transfer,
                      text: 'Quản lý cần gán xe tải cho tài xế trước.',
                    )
                  else if (trips.isEmpty)
                    const _EmptyState(
                      icon: Icons.route_outlined,
                      text: 'Chưa có chuyến xe được phân công.',
                    )
                  else
                    ...trips.map(
                      (trip) => _TripCard(trip: trip, onUpdate: onUpdate),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _DriverSummary extends StatelessWidget {
  const _DriverSummary({required this.profile, required this.trips});

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> trips;

  @override
  Widget build(BuildContext context) {
    final activeTrips = trips.where(
      (trip) => !['DA_HOAN_THANH', 'DA_HUY'].contains(trip['trang_thai']),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
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
          final compact = constraints.maxWidth < 560;
          final identity = Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${profile['ho_ten'] ?? 'Tài xế xe tải'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile['bien_so_xe'] == null
                          ? 'Chưa được gán xe tải'
                          : '${profile['bien_so_xe']}  |  ${_weight(profile['tai_trong'])}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final workload = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  '${activeTrips.length} chuyến đang xử lý',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 16), workload],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 20),
              workload,
            ],
          );
        },
      ),
    );
  }

  static String _weight(dynamic value) {
    final number = value is num ? value : num.tryParse('$value');
    if (number == null) return 'Chưa có tải trọng';
    return '${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)} kg';
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onUpdate});

  final Map<String, dynamic> trip;
  final Future<void> Function(int, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = '${trip['trang_thai']}';
    final stages = List<Map<String, dynamic>>.from(
      (trip['chang_duong'] as List?) ?? const [],
    );
    final next = switch (status) {
      'CHO_KHOI_HANH' || 'DANG_XEP_HANG' => ('DANG_DI', 'Bắt đầu chạy'),
      'DANG_DI' => ('DA_DEN', 'Đã đến kho'),
      'DA_DEN' => ('DA_HOAN_THANH', 'Hoàn thành chuyến'),
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            color: _statusBackground(status, colors),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_statusIcon(status), color: AppColors.primary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trip['ma_chuyen']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trip['bien_so_xe']}  |  ${trip['so_don_hang'] ?? 0} kiện',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _TripStatusLabel(status: status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.alt_route_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Chặng đường di chuyển',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (trip['da_niem_phong'] == true)
                      Tooltip(
                        message: 'Xe đã được niêm phong',
                        child: const Icon(
                          Icons.lock_rounded,
                          color: AppColors.success,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (stages.isEmpty)
                  _MissingRoute(
                    from: '${trip['kho_di_ten'] ?? 'Chưa xác định'}',
                    to: '${trip['kho_den_ten'] ?? 'Chưa xác định'}',
                  )
                else
                  ...stages.map(
                    (stage) =>
                        _RouteStage(stage: stage, currentTripStatus: status),
                  ),
                const SizedBox(height: 4),
                if (trip['da_niem_phong'] == true) ...[
                  const _SealInformation(),
                  const SizedBox(height: 12),
                ],
                _TripActions(
                  trip: trip,
                  stages: stages,
                  next: next,
                  onUpdate: onUpdate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusBackground(String status, ColorScheme colors) =>
      switch (status) {
        'DANG_DI' => AppColors.primary10,
        'DA_DEN' => AppColors.success.withValues(alpha: 0.1),
        'DA_HOAN_THANH' => colors.surfaceContainerHighest,
        _ => colors.surface,
      };

  IconData _statusIcon(String status) => switch (status) {
    'DANG_DI' => Icons.local_shipping_rounded,
    'DA_DEN' => Icons.warehouse_rounded,
    'DA_HOAN_THANH' => Icons.task_alt_rounded,
    _ => Icons.schedule_rounded,
  };
}

class _RouteStage extends StatelessWidget {
  const _RouteStage({required this.stage, required this.currentTripStatus});

  final Map<String, dynamic> stage;
  final String currentTripStatus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stageStatus = '${stage['trang_thai'] ?? 'CHO_KHOI_HANH'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Chặng ${stage['thu_tu_chuyen'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                _stageStatus(stageStatus, currentTripStatus),
                style: TextStyle(
                  color: _stageColor(stageStatus, currentTripStatus),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _WarehousePoint(
            icon: Icons.trip_origin_rounded,
            label: 'Kho xuất phát',
            name: '${stage['kho_di_ten'] ?? 'Chưa xác định'}',
            code: '${stage['kho_di_ma'] ?? ''}',
            address: '${stage['kho_di_dia_chi'] ?? ''}',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Container(
              height: 28,
              width: 2,
              alignment: Alignment.centerLeft,
              child: Container(width: 2, color: colors.outlineVariant),
            ),
          ),
          _WarehousePoint(
            icon: Icons.location_on_rounded,
            label: 'Kho đến',
            name: '${stage['kho_den_ten'] ?? 'Chưa xác định'}',
            code: '${stage['kho_den_ma'] ?? ''}',
            address: '${stage['kho_den_dia_chi'] ?? ''}',
          ),
          if (stage['ngay_den_du_kien'] != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Dự kiến đến: ${_formatDate(stage['ngay_den_du_kien'])}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _stageStatus(String stageStatus, String tripStatus) {
    if (stageStatus == 'DA_DEN') return 'Đã đến';
    if (stageStatus == 'DANG_DI' || tripStatus == 'DANG_DI') {
      return 'Đang di chuyển';
    }
    return 'Chờ khởi hành';
  }

  static Color _stageColor(String stageStatus, String tripStatus) {
    if (stageStatus == 'DA_DEN') return AppColors.success;
    if (stageStatus == 'DANG_DI' || tripStatus == 'DANG_DI') {
      return AppColors.primary;
    }
    return AppColors.textSecondary;
  }

  static String _formatDate(dynamic raw) {
    final value = DateTime.tryParse('$raw')?.toLocal();
    if (value == null) return '$raw';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)} ${two(value.day)}/${two(value.month)}/${value.year}';
  }
}

class _WarehousePoint extends StatelessWidget {
  const _WarehousePoint({
    required this.icon,
    required this.label,
    required this.name,
    required this.code,
    required this.address,
  });

  final IconData icon;
  final String label;
  final String name;
  final String code;
  final String address;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                code.isEmpty ? name : '$name ($code)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  address,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TripActions extends StatelessWidget {
  const _TripActions({
    required this.trip,
    required this.stages,
    required this.next,
    required this.onUpdate,
  });

  final Map<String, dynamic> trip;
  final List<Map<String, dynamic>> stages;
  final (String, String)? next;
  final Future<void> Function(int, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? nextStage;
    for (final stage in stages) {
      if (stage['trang_thai'] != 'DA_DEN') {
        nextStage = stage;
        break;
      }
    }
    nextStage ??= stages.isEmpty ? null : stages.last;
    final routeStage =
        nextStage ??
        <String, dynamic>{
          'kho_den_ten': trip['kho_den_ten'],
          'kho_den_dia_chi': trip['kho_den_ten'],
        };
    final destination =
        '${routeStage['kho_den_dia_chi'] ?? routeStage['kho_den_ten'] ?? ''}';
    final directions = OutlinedButton.icon(
      onPressed: destination.trim().isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TransportDriverNavigationScreen(
                  trip: trip,
                  stage: routeStage,
                ),
              ),
            ),
      icon: const Icon(Icons.directions_rounded),
      label: const Text('Mở chỉ đường'),
    );
    final update = next == null
        ? null
        : FilledButton.icon(
            onPressed: () => onUpdate((trip['id'] as num).toInt(), next!.$1),
            icon: Icon(_actionIcon(next!.$1)),
            label: Text(next!.$2),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 48, child: directions),
              if (update != null) ...[
                const SizedBox(height: 9),
                SizedBox(height: 50, child: update),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: SizedBox(height: 48, child: directions)),
            if (update != null) ...[
              const SizedBox(width: 10),
              Expanded(child: SizedBox(height: 48, child: update)),
            ],
          ],
        );
      },
    );
  }

  IconData _actionIcon(String status) => switch (status) {
    'DANG_DI' => Icons.play_arrow_rounded,
    'DA_DEN' => Icons.warehouse_rounded,
    _ => Icons.task_alt_rounded,
  };
}

class _TripStatusLabel extends StatelessWidget {
  const _TripStatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _label(status),
      style: TextStyle(
        color: _color(status),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );

  static String _label(String value) => switch (value) {
    'CHO_KHOI_HANH' => 'Chờ khởi hành',
    'DANG_XEP_HANG' => 'Đang xếp hàng',
    'DANG_DI' => 'Đang di chuyển',
    'DA_DEN' => 'Đã đến kho',
    'DA_HOAN_THANH' => 'Hoàn thành',
    'DA_HUY' => 'Đã hủy',
    _ => value,
  };

  static Color _color(String value) => switch (value) {
    'DA_HOAN_THANH' || 'DA_DEN' => AppColors.success,
    'DA_HUY' => AppColors.error,
    _ => AppColors.primary,
  };
}

class _SealInformation extends StatelessWidget {
  const _SealInformation();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_rounded, color: AppColors.success, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Xe đã được niêm phong',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MissingRoute extends StatelessWidget {
  const _MissingRoute({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.route_outlined, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text('$from → $to')),
      ],
    ),
  );
}

class _TripsLoadingView extends StatelessWidget {
  const _TripsLoadingView();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              children: [
                _SkeletonBlock(height: 108, color: color),
                const SizedBox(height: 26),
                _SkeletonBlock(height: 28, color: color, widthFactor: 0.42),
                const SizedBox(height: 12),
                _SkeletonBlock(height: 340, color: color),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    required this.color,
    this.widthFactor = 1,
  });

  final double height;
  final Color color;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    ),
  );
}

enum _HistoryFilter { all, completed, cancelled }

class _TripHistoryView extends StatefulWidget {
  const _TripHistoryView({required this.trips});

  final List<Map<String, dynamic>> trips;

  @override
  State<_TripHistoryView> createState() => _TripHistoryViewState();
}

class _TripHistoryViewState extends State<_TripHistoryView> {
  final _searchController = TextEditingController();
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final completed = widget.trips
        .where((trip) => trip['trang_thai'] == 'DA_HOAN_THANH')
        .length;
    final cancelled = widget.trips
        .where((trip) => trip['trang_thai'] == 'DA_HUY')
        .length;
    final visibleTrips = widget.trips.where((trip) {
      final status = '${trip['trang_thai']}';
      final matchesFilter = switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.completed => status == 'DA_HOAN_THANH',
        _HistoryFilter.cancelled => status == 'DA_HUY',
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      final searchable = [
        trip['ma_chuyen'],
        trip['bien_so_xe'],
        trip['kho_di_ten'],
        trip['kho_den_ten'],
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            32,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HistorySummary(
                      total: widget.trips.length,
                      completed: completed,
                      cancelled: cancelled,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Tìm mã chuyến, biển số hoặc kho',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Xóa tìm kiếm',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _HistoryFilterChip(
                            label: 'Tất cả',
                            count: widget.trips.length,
                            selected: _filter == _HistoryFilter.all,
                            onSelected: () =>
                                setState(() => _filter = _HistoryFilter.all),
                          ),
                          const SizedBox(width: 8),
                          _HistoryFilterChip(
                            label: 'Hoàn thành',
                            count: completed,
                            selected: _filter == _HistoryFilter.completed,
                            onSelected: () => setState(
                              () => _filter = _HistoryFilter.completed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _HistoryFilterChip(
                            label: 'Đã hủy',
                            count: cancelled,
                            selected: _filter == _HistoryFilter.cancelled,
                            onSelected: () => setState(
                              () => _filter = _HistoryFilter.cancelled,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Các chuyến đã xử lý',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${visibleTrips.length} chuyến',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (visibleTrips.isEmpty)
                      _EmptyState(
                        icon: query.isEmpty
                            ? Icons.history_toggle_off_rounded
                            : Icons.search_off_rounded,
                        text: query.isEmpty
                            ? 'Chưa có chuyến nào trong mục này.'
                            : 'Không tìm thấy chuyến phù hợp.',
                      )
                    else
                      ...visibleTrips.map(
                        (trip) => _HistoryTripTile(
                          trip: trip,
                          onTap: () => _showTripHistoryDetails(context, trip),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showTripHistoryDetails(
    BuildContext context,
    Map<String, dynamic> trip,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _TripHistoryDetails(trip: trip),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({
    required this.total,
    required this.completed,
    required this.cancelled,
  });

  final int total;
  final int completed;
  final int cancelled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.primary10,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final heading = Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.history_rounded, color: Colors.white),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nhật ký vận chuyển',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 2),
                  Text('Theo dõi lại các chuyến xe đã xử lý'),
                ],
              ),
            ),
          ],
        );
        final metrics = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HistoryMetric(value: '$total', label: 'Tổng'),
            const SizedBox(width: 22),
            _HistoryMetric(value: '$completed', label: 'Hoàn thành'),
            if (cancelled > 0) ...[
              const SizedBox(width: 22),
              _HistoryMetric(value: '$cancelled', label: 'Đã hủy'),
            ],
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: metrics,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            metrics,
          ],
        );
      },
    ),
  );
}

class _HistoryMetric extends StatelessWidget {
  const _HistoryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _HistoryFilterChip extends StatelessWidget {
  const _HistoryFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    onSelected: (_) => onSelected(),
    avatar: selected ? const Icon(Icons.check_rounded, size: 18) : null,
    label: Text('$label ($count)'),
  );
}

class _HistoryTripTile extends StatelessWidget {
  const _HistoryTripTile({required this.trip, required this.onTap});

  final Map<String, dynamic> trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = '${trip['trang_thai']}';
    final completed = status == 'DA_HOAN_THANH';
    final date =
        trip['ngay_den_thuc_te'] ??
        trip['ngay_khoi_hanh'] ??
        trip['ngay_du_kien'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: completed
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  completed ? Icons.task_alt_rounded : Icons.cancel_outlined,
                  color: completed ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${trip['ma_chuyen']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _TripStatusLabel(status: status),
                    const SizedBox(height: 9),
                    Text(
                      '${trip['kho_di_ten'] ?? 'Chưa xác định'} → ${trip['kho_den_ten'] ?? 'Chưa xác định'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 14,
                      runSpacing: 5,
                      children: [
                        _HistoryMeta(
                          icon: Icons.local_shipping_outlined,
                          text: '${trip['bien_so_xe'] ?? 'Chưa có biển số'}',
                        ),
                        _HistoryMeta(
                          icon: Icons.inventory_2_outlined,
                          text: '${trip['so_don_hang'] ?? 0} kiện',
                        ),
                        if (date != null)
                          _HistoryMeta(
                            icon: Icons.schedule_rounded,
                            text: _historyDate(date),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMeta extends StatelessWidget {
  const _HistoryMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    ],
  );
}

class _TripHistoryDetails extends StatelessWidget {
  const _TripHistoryDetails({required this.trip});

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final status = '${trip['trang_thai']}';
    final stages = List<Map<String, dynamic>>.from(
      (trip['chang_duong'] as List?) ?? const [],
    );
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trip['ma_chuyen']}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trip['bien_so_xe'] ?? 'Chưa có biển số'}  |  ${trip['so_don_hang'] ?? 0} kiện',
                      ),
                    ],
                  ),
                ),
                _TripStatusLabel(status: status),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _HistoryTimeLine(trip: trip),
                if (trip['da_niem_phong'] == true) ...[
                  const SizedBox(height: 14),
                  const _SealInformation(),
                ],
                const SizedBox(height: 22),
                Text(
                  'Hành trình qua các kho',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (stages.isEmpty)
                  _MissingRoute(
                    from: '${trip['kho_di_ten'] ?? 'Chưa xác định'}',
                    to: '${trip['kho_den_ten'] ?? 'Chưa xác định'}',
                  )
                else
                  ...stages.map(
                    (stage) =>
                        _RouteStage(stage: stage, currentTripStatus: status),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTimeLine extends StatelessWidget {
  const _HistoryTimeLine({required this.trip});

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final values = <(IconData, String, dynamic)>[
      (Icons.play_circle_outline_rounded, 'Khởi hành', trip['ngay_khoi_hanh']),
      (Icons.event_outlined, 'Dự kiến đến', trip['ngay_du_kien']),
      (Icons.flag_outlined, 'Đến thực tế', trip['ngay_den_thuc_te']),
    ].where((item) => item.$3 != null).toList();
    if (values.isEmpty) {
      return const _EmptyState(
        icon: Icons.event_busy_outlined,
        text: 'Chuyến này chưa có thông tin thời gian.',
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 14,
        children: values
            .map(
              (item) => _HistoryMeta(
                icon: item.$1,
                text: '${item.$2}: ${_historyDate(item.$3, includeTime: true)}',
              ),
            )
            .toList(),
      ),
    );
  }
}

String _historyDate(dynamic raw, {bool includeTime = false}) {
  final value = DateTime.tryParse('$raw')?.toLocal();
  if (value == null) return '$raw';
  String two(int number) => number.toString().padLeft(2, '0');
  final date = '${two(value.day)}/${two(value.month)}/${value.year}';
  return includeTime ? '${two(value.hour)}:${two(value.minute)} $date' : date;
}

class _DriverAccount extends StatelessWidget {
  const _DriverAccount({
    required this.profile,
    required this.name,
    required this.onLogout,
  });
  final Map<String, dynamic> profile;
  final String name;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const CircleAvatar(
        radius: 42,
        backgroundColor: AppColors.primary,
        child: Icon(Icons.fire_truck, color: Colors.white, size: 44),
      ),
      const SizedBox(height: 12),
      Text(
        name,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const Text('Tài xế xe tải', textAlign: TextAlign.center),
      const SizedBox(height: 22),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text('${profile['so_dien_thoai'] ?? ''}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text('${profile['bien_so_xe'] ?? 'Chưa gán xe'}'),
              subtitle: Text(
                'Trạng thái: ${profile['xe_trang_thai'] ?? 'Chưa có'}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout),
        label: const Text('Đăng xuất'),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(36),
    child: Column(
      children: [
        Icon(icon, size: 52, color: AppColors.textDisabled),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 52),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}
