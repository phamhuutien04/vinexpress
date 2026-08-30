import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../services/order_service.dart';
import '../../widgets/vietnam_island_markers.dart';
import 'widgets/customer_design.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _service = OrderService();
  final _mapController = MapController();
  final Map<String, LatLng?> _geocodeCache = {};
  Timer? _timer;
  Map<String, dynamic>? _tracking;
  LatLng? _currentPoint;
  LatLng? _destinationPoint;
  List<LatLng> _route = const [];
  double? _distanceKm;
  int? _etaMinutes;
  String? _routeSignature;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final tracking = await _service.getCustomerOrderTracking(widget.orderId);
      final current = await _trackingPoint(
        tracking,
        latKey: 'vi_tri_vi_do',
        lngKey: 'vi_tri_kinh_do',
        addressKey: 'vi_tri_dia_chi',
      );
      final destination = await _trackingPoint(
        tracking,
        latKey: 'diem_den_vi_do',
        lngKey: 'diem_den_kinh_do',
        addressKey: 'diem_den_dia_chi',
      );
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _currentPoint = current;
        _destinationPoint = destination;
        _loading = false;
        _error = null;
      });
      await _updateRoute(current, destination);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is OrderServiceException
            ? error.message
            : 'Không thể cập nhật hành trình đơn hàng.';
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<LatLng?> _trackingPoint(
    Map<String, dynamic> data, {
    required String latKey,
    required String lngKey,
    required String addressKey,
  }) async {
    final lat = (data[latKey] as num?)?.toDouble();
    final lng = (data[lngKey] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    final address = '${data[addressKey] ?? ''}'.trim();
    return address.isEmpty ? null : _geocode(address);
  }

  Future<LatLng?> _geocode(String address) async {
    if (_geocodeCache.containsKey(address)) return _geocodeCache[address];
    try {
      final response = await http
          .get(
            Uri.https('photon.komoot.io', '/api/', {
              'q': '$address, Việt Nam',
              'limit': '1',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final features = (json as Map<String, dynamic>)['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final geometry = Map<String, dynamic>.from(
        (features.first as Map)['geometry'] as Map,
      );
      final pair = geometry['coordinates'] as List;
      final point = LatLng(
        (pair[1] as num).toDouble(),
        (pair[0] as num).toDouble(),
      );
      final result = _isInVietnam(point) ? point : null;
      _geocodeCache[address] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  bool _isInVietnam(LatLng point) =>
      point.latitude >= 8 &&
      point.latitude <= 24 &&
      point.longitude >= 102 &&
      point.longitude <= 110;

  Future<void> _updateRoute(LatLng? from, LatLng? to) async {
    if (from == null || to == null) {
      if (!mounted) return;
      setState(() {
        _route = const [];
        _distanceKm = null;
        _etaMinutes = null;
      });
      return;
    }
    final signature =
        '${from.latitude.toStringAsFixed(3)},${from.longitude.toStringAsFixed(3)};'
        '${to.latitude.toStringAsFixed(3)},${to.longitude.toStringAsFixed(3)}';
    if (_routeSignature != signature) {
      await _loadRoadRoute(from, to);
      _routeSignature = signature;
    }
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: [from, to, ..._route],
          padding: const EdgeInsets.fromLTRB(42, 55, 42, 55),
          maxZoom: 16,
        ),
      );
    });
  }

  Future<void> _loadRoadRoute(LatLng from, LatLng to) async {
    try {
      final points = _vietnamRoadPoints(from, to);
      final coordinates = points
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final response = await http
          .get(
            Uri.https(
              'router.project-osrm.org',
              '/route/v1/driving/$coordinates',
              {'overview': 'full', 'geometries': 'geojson'},
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final routes = (json as Map<String, dynamic>)['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final route = Map<String, dynamic>.from(routes.first as Map);
      final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
      _route = (geometry['coordinates'] as List).map((value) {
        final pair = value as List;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      _distanceKm = (route['distance'] as num).toDouble() / 1000;
      _etaMinutes = ((route['duration'] as num).toDouble() / 60).ceil();
    } catch (_) {
      // Vẫn hiển thị hai vị trí nếu dịch vụ tuyến đường tạm thời không phản hồi.
    }
  }

  List<LatLng> _vietnamRoadPoints(LatLng from, LatLng to) {
    const corridor = <LatLng>[
      LatLng(10.7769, 106.7009),
      LatLng(10.9805, 108.2615),
      LatLng(12.2388, 109.1967),
      LatLng(13.7820, 109.2194),
      LatLng(15.1214, 108.8044),
      LatLng(16.0544, 108.2022),
      LatLng(17.4689, 106.6223),
      LatLng(18.6796, 105.6813),
      LatLng(19.8067, 105.7852),
      LatLng(21.0285, 105.8542),
    ];
    final distance = const Distance().as(LengthUnit.Kilometer, from, to);
    if (distance < 280) return [from, to];
    final minLat = from.latitude < to.latitude ? from.latitude : to.latitude;
    final maxLat = from.latitude > to.latitude ? from.latitude : to.latitude;
    var middle = corridor
        .where((p) => p.latitude > minLat + .12 && p.latitude < maxLat - .12)
        .toList();
    if (to.latitude < from.latitude) middle = middle.reversed.toList();
    return [from, ...middle, to];
  }

  @override
  Widget build(BuildContext context) {
    final data = _tracking;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          data == null ? 'Theo dõi đơn hàng' : '${data['ma_van_don']}',
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const _TrackingSkeleton()
          : _error != null && data == null
          ? _ErrorView(message: _error!, retry: _refresh)
          : _TrackingBody(
              data: data!,
              current: _currentPoint,
              destination: _destinationPoint,
              route: _route,
              mapController: _mapController,
              distanceKm: _distanceKm,
              etaMinutes: _etaMinutes,
              error: _error,
            ),
    );
  }
}

class _TrackingBody extends StatelessWidget {
  const _TrackingBody({
    required this.data,
    required this.current,
    required this.destination,
    required this.route,
    required this.mapController,
    required this.distanceKm,
    required this.etaMinutes,
    required this.error,
  });

  final Map<String, dynamic> data;
  final LatLng? current;
  final LatLng? destination;
  final List<LatLng> route;
  final MapController mapController;
  final double? distanceKm;
  final int? etaMinutes;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: current == null
            ? _WaitingForPosition(data: data)
            : FlutterMap(
                mapController: mapController,
                options: MapOptions(initialCenter: current!, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.vinexpress.app',
                    maxZoom: 19,
                  ),
                  if (route.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          strokeWidth: 7,
                          color: AppColors.primary,
                          borderStrokeWidth: 3,
                          borderColor: Colors.white,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      ...vietnamIslandMarkers,
                      Marker(
                        point: current!,
                        width: 54,
                        height: 54,
                        child: _MapPin(
                          icon: data['tracking_mode'] == 'XE_TAI'
                              ? Icons.local_shipping
                              : data['tracking_mode'] == 'KHO'
                              ? Icons.warehouse
                              : Icons.delivery_dining,
                          color: AppColors.primary,
                        ),
                      ),
                      if (destination != null)
                        Marker(
                          point: destination!,
                          width: 54,
                          height: 54,
                          child: const _MapPin(
                            icon: Icons.location_on,
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
      _TrackingSummary(
        data: data,
        distanceKm: distanceKm,
        etaMinutes: etaMinutes,
        error: error,
      ),
    ],
  );
}

class _TrackingSummary extends StatelessWidget {
  const _TrackingSummary({
    required this.data,
    required this.distanceKm,
    required this.etaMinutes,
    required this.error,
  });

  final Map<String, dynamic> data;
  final double? distanceKm;
  final int? etaMinutes;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final mode = '${data['tracking_mode'] ?? 'SHIPPER'}';
    final updated = DateTime.tryParse(
      '${data['vi_tri_cap_nhat_luc']}',
    )?.toLocal();
    final title = switch (mode) {
      'XE_TAI' => 'Đang trên xe ${data['bien_so_xe'] ?? ''}',
      'KHO' => 'Đang ở ${data['vi_tri_ten'] ?? 'kho trung chuyển'}',
      _ => '${data['vi_tri_ten'] ?? 'Đang chờ nhân viên cập nhật'}',
    };
    final history = (data['lich_su'] as List?) ?? const [];
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 330),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .12),
              blurRadius: 18,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ModeIcon(mode: mode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          mode == 'KHO'
                              ? 'Kiện hàng đang được xử lý tại kho'
                              : mode == 'XE_TAI'
                              ? 'Vị trí xe được cập nhật tự động'
                              : 'Vị trí nhân viên đang giữ kiện',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: '${data['trang_thai'] ?? ''}'),
                ],
              ),
              if (mode == 'XE_TAI') ...[
                const SizedBox(height: 12),
                Text(
                  'Chuyến ${data['ma_chuyen'] ?? ''}'
                  '${data['tai_xe_ten'] == null ? '' : ' • ${data['tai_xe_ten']}'}',
                ),
              ],
              if (distanceKm != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Còn ${distanceKm!.toStringAsFixed(1)} km'
                  '${etaMinutes == null ? '' : ' • dự kiến $etaMinutes phút'}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (updated != null) ...[
                const SizedBox(height: 7),
                Text(
                  'Cập nhật lúc ${_time(updated)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hành trình hàng hóa',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showJourney(context, data),
                    icon: const Icon(Icons.route, size: 19),
                    label: const Text('Xem toàn bộ'),
                  ),
                ],
              ),
              if (history.isEmpty)
                const Text('Bấm “Xem toàn bộ” để xem tuyến qua các kho.')
              else
                _HistoryItem(
                  data: Map<String, dynamic>.from(history.first as Map),
                ),
              if (error != null) ...[
                const SizedBox(height: 7),
                Text(error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _time(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  void _showJourney(BuildContext context, Map<String, dynamic> data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JourneySheet(data: data),
    );
  }
}

class _JourneySheet extends StatelessWidget {
  const _JourneySheet({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final stages = ((data['cac_chang'] as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where(_hasCargoActuallyTravelled)
        .toList();
    final history = ((data['lich_su'] as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: .82,
      minChildSize: .55,
      maxChildSize: .96,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.route, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hành trình kiện hàng',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('${data['ma_van_don'] ?? ''}'),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Các mốc đã ghi nhận',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            _JourneyMilestone(
              icon: Icons.inventory_2_outlined,
              title: 'Điểm gửi hàng',
              subtitle: '${data['nguoi_gui_dia_chi'] ?? ''}',
              time: _parseDate(data['ngay_tao']),
              complete: true,
              first: true,
            ),
            for (var index = 0; index < stages.length; index++)
              _JourneyMilestone(
                icon: Icons.local_shipping_outlined,
                title:
                    '${stages[index]['kho_di_ten'] ?? 'Kho đi'} đến '
                    '${stages[index]['kho_den_ten'] ?? 'Kho đến'}',
                subtitle:
                    'Chuyến ${stages[index]['ma_chuyen'] ?? ''}'
                    '${stages[index]['bien_so_xe'] == null ? '' : ' • ${stages[index]['bien_so_xe']}'}',
                time: _parseDate(
                  stages[index]['ngay_den'] ?? stages[index]['ngay_khoi_hanh'],
                ),
                complete: true,
              ),
            _JourneyMilestone(
              icon: data['tracking_mode'] == 'XE_TAI'
                  ? Icons.local_shipping_outlined
                  : data['tracking_mode'] == 'KHO'
                  ? Icons.warehouse_outlined
                  : Icons.delivery_dining_outlined,
              title: '${data['vi_tri_ten'] ?? 'Vị trí hiện tại'}',
              subtitle:
                  '${data['vi_tri_dia_chi'] ?? data['kho_den_dia_chi'] ?? ''}',
              time: _parseDate(data['vi_tri_cap_nhat_luc']),
              current: true,
              last: true,
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Nhật ký xử lý',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (final item in history) _HistoryItem(data: item),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.tryParse('$value')?.toLocal();

  static bool _hasCargoActuallyTravelled(Map<String, dynamic> stage) {
    final tripStatus = '${stage['trang_thai'] ?? ''}';
    final cargoStatus = '${stage['kien_tren_xe_trang_thai'] ?? ''}';
    return const {'DANG_DI', 'DA_DEN', 'DA_HOAN_THANH'}.contains(tripStatus) ||
        const {'DANG_VAN_CHUYEN', 'DA_DO_HANG'}.contains(cargoStatus);
  }
}

class _JourneyMilestone extends StatelessWidget {
  const _JourneyMilestone({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.time,
    this.complete = false,
    this.current = false,
    this.first = false,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime? time;
  final bool complete;
  final bool current;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final active = complete || current;
    final color = active ? AppColors.primary : Colors.grey.shade400;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 82),
      child: Stack(
        children: [
          if (!first)
            Positioned(
              left: 17,
              top: 0,
              height: 8,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          if (!last)
            Positioned(
              left: 17,
              top: 44,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary.withValues(alpha: .13)
                        : Colors.grey.shade100,
                    shape: BoxShape.circle,
                    border: current
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: current
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: current ? AppColors.primary : null,
                        ),
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle),
                      ],
                      if (time != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${time!.day.toString().padLeft(2, '0')}/'
                          '${time!.month.toString().padLeft(2, '0')}/'
                          '${time!.year}  '
                          '${time!.hour.toString().padLeft(2, '0')}:'
                          '${time!.minute.toString().padLeft(2, '0')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeIcon extends StatelessWidget {
  const _ModeIcon({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(
      mode == 'XE_TAI'
          ? Icons.local_shipping
          : mode == 'KHO'
          ? Icons.warehouse
          : Icons.delivery_dining,
      color: AppColors.primary,
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _label(status),
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  String _label(String value) => switch (value) {
    'CHO_LAY_HANG' => 'Chờ lấy hàng',
    'DA_LAY_HANG' => 'Đã lấy hàng',
    'DANG_VAN_CHUYEN' => 'Đang vận chuyển',
    'DEN_KHO_TRUNG_CHUYEN' => 'Đã đến kho trung chuyển',
    'DEN_KHO_DICH' => 'Đã đến kho đích',
    'GIAO_CHO_SHIPPER' => 'Chờ giao hàng',
    'DANG_GIAO_HANG' => 'Đang giao hàng',
    'DA_GIAO_HANG' => 'Đã giao hàng',
    _ => value.replaceAll('_', ' ').toLowerCase(),
  };
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final time = DateTime.tryParse('${data['thoi_gian']}')?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 9, color: AppColors.primary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${data['hanh_dong'] ?? data['trang_thai'] ?? 'Cập nhật đơn hàng'}'
              '${data['kho_ten'] == null ? '' : ' • ${data['kho_ten']}'}',
            ),
          ),
          if (time != null)
            Text(
              '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:'
              '${time.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
    ),
    child: Icon(icon, color: Colors.white),
  );
}

class _WaitingForPosition extends StatelessWidget {
  const _WaitingForPosition({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route_outlined, size: 66, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(
            data['tracking_mode'] == 'KHO'
                ? 'Đơn đang được xử lý tại ${data['vi_tri_ten'] ?? 'kho trung chuyển'}'
                : 'Đang chờ nhân viên cập nhật vị trí',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _TrackingSkeleton extends StatelessWidget {
  const _TrackingSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        Expanded(child: CustomerSkeleton(height: double.infinity, radius: 20)),
        SizedBox(height: 12),
        CustomerConstrained(child: CustomerSkeleton(height: 210, radius: 20)),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 56),
          const SizedBox(height: 12),
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
