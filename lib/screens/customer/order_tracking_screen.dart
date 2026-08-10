import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../services/order_service.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _service = OrderService();
  final _mapController = MapController();
  Timer? _timer;
  Map<String, dynamic>? _tracking;
  List<LatLng> _route = [];
  double? _distanceKm;
  int? _etaMinutes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final tracking = await _service.getCustomerOrderTracking(widget.orderId);
      final shipper = _point(tracking, 'shipper_vi_do', 'shipper_kinh_do');
      final destination = _point(
        tracking,
        'diem_den_vi_do',
        'diem_den_kinh_do',
      );
      if (shipper != null && destination != null) {
        await _loadRoadRoute(shipper, destination);
      } else {
        _route = [];
        _distanceKm = null;
        _etaMinutes = null;
      }
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _loading = false;
        _error = null;
      });
      if (shipper != null && destination != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.fitCamera(
              CameraFit.coordinates(
                coordinates: [shipper, destination, ..._route],
                padding: const EdgeInsets.all(55),
              ),
            );
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is OrderServiceException
            ? error.message
            : 'Không thể cập nhật vị trí shipper.';
      });
    }
  }

  LatLng? _point(Map<String, dynamic> data, String latKey, String lngKey) {
    final lat = data[latKey] as num?;
    final lng = data[lngKey] as num?;
    return lat == null || lng == null
        ? null
        : LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<void> _loadRoadRoute(LatLng from, LatLng to) async {
    final path =
        '/route/v1/driving/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}';
    final response = await http
        .get(
          Uri.https('router.project-osrm.org', path, {
            'overview': 'full',
            'geometries': 'geojson',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return;
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final routes = (json as Map<String, dynamic>)['routes'] as List?;
    if (routes == null || routes.isEmpty) return;
    final route = Map<String, dynamic>.from(routes.first as Map);
    final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
    final coordinates = geometry['coordinates'] as List;
    _route = coordinates.map((value) {
      final pair = value as List;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();
    _distanceKm = (route['distance'] as num).toDouble() / 1000;
    _etaMinutes = ((route['duration'] as num).toDouble() / 60).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final data = _tracking;
    final shipper = data == null
        ? null
        : _point(data, 'shipper_vi_do', 'shipper_kinh_do');
    final destination = data == null
        ? null
        : _point(data, 'diem_den_vi_do', 'diem_den_kinh_do');
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null && data == null
          ? _ErrorView(message: _error!, retry: _refresh)
          : Column(
              children: [
                Expanded(
                  child: shipper == null || destination == null
                      ? const _WaitingForShipper()
                      : FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: shipper,
                            initialZoom: 14,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.vinexpress.app',
                            ),
                            if (_route.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _route,
                                    strokeWidth: 6,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: shipper,
                                  width: 52,
                                  height: 52,
                                  child: const _MapPin(
                                    icon: Icons.delivery_dining,
                                    color: Colors.blue,
                                  ),
                                ),
                                Marker(
                                  point: destination,
                                  width: 52,
                                  height: 52,
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
                  data: data!,
                  distanceKm: _distanceKm,
                  etaMinutes: _etaMinutes,
                  error: _error,
                ),
              ],
            ),
    );
  }
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
    final updated = DateTime.tryParse(
      '${data['vi_tri_cap_nhat_luc']}',
    )?.toLocal();
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 14)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etaMinutes == null
                  ? 'Đang xác định thời gian đến'
                  : 'Dự kiến đến sau $etaMinutes phút',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              distanceKm == null
                  ? 'Đang chờ tuyến đường'
                  : 'Còn ${distanceKm!.toStringAsFixed(1)} km theo đường bộ',
            ),
            const SizedBox(height: 12),
            Text('${data['shipper_ten'] ?? 'Đang chờ phân công shipper'}'),
            const SizedBox(height: 4),
            Text(
              '${data['diem_den_dia_chi'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (updated != null) ...[
              const SizedBox(height: 8),
              Text(
                'Vị trí cập nhật lúc '
                '${updated.hour.toString().padLeft(2, '0')}:'
                '${updated.minute.toString().padLeft(2, '0')}:'
                '${updated.second.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
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

class _WaitingForShipper extends StatelessWidget {
  const _WaitingForShipper();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delivery_dining_outlined,
            size: 66,
            color: AppColors.primary,
          ),
          SizedBox(height: 14),
          Text(
            'Đang chờ shipper nhận đơn hoặc cập nhật vị trí',
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
