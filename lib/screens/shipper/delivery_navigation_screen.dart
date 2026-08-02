import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../services/shipper_service.dart';

class DeliveryNavigationScreen extends StatefulWidget {
  const DeliveryNavigationScreen({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  State<DeliveryNavigationScreen> createState() =>
      _DeliveryNavigationScreenState();
}

class _DeliveryNavigationScreenState extends State<DeliveryNavigationScreen> {
  final _mapController = MapController();
  final _shipperService = ShipperService();
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _shipper;
  LatLng? _pickup;
  LatLng? _delivery;
  List<LatLng> _route = [];
  bool _toReceiver = false;
  bool _loadingRoute = true;
  bool _updatingStatus = false;
  double? _distanceKm;
  double? _durationMinutes;
  String? _error;

  LatLng get _target => (_toReceiver ? _delivery : _pickup)!;

  @override
  void initState() {
    super.initState();
    _prepareNavigation();
  }

  Future<void> _prepareNavigation() async {
    try {
      _pickup = _coordinatesFromOrder('nguoi_gui_vi_do', 'nguoi_gui_kinh_do');
      _delivery = _coordinatesFromOrder(
        'nguoi_nhan_vi_do',
        'nguoi_nhan_kinh_do',
      );
      _pickup ??= await _coordinatesForAddress(
        '${widget.order['nguoi_gui_dia_chi'] ?? ''}',
      );
      _delivery ??= await _coordinatesForAddress(
        '${widget.order['nguoi_nhan_dia_chi'] ?? ''}',
      );
      if (_pickup == null || _delivery == null) {
        throw Exception('missing coordinates');
      }
      if (!mounted) return;
      setState(() {});
      await _startTracking();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
        _error =
            'Đơn hàng chưa có tọa độ hợp lệ. Hãy kiểm tra lại địa chỉ lấy và giao hàng.';
      });
    }
  }

  LatLng? _coordinatesFromOrder(String latitudeKey, String longitudeKey) {
    final latitude = widget.order[latitudeKey];
    final longitude = widget.order[longitudeKey];
    final latitudeNumber = latitude is num
        ? latitude.toDouble()
        : double.tryParse('$latitude');
    final longitudeNumber = longitude is num
        ? longitude.toDouble()
        : double.tryParse('$longitude');
    if (latitudeNumber == null || longitudeNumber == null) return null;
    return LatLng(latitudeNumber, longitudeNumber);
  }

  Future<LatLng?> _coordinatesForAddress(String address) async {
    if (address.trim().isEmpty) return null;
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': address,
      'countrycodes': 'vn',
      'limit': '1',
    });
    final response = await http
        .get(uri, headers: const {'User-Agent': 'VinExpress Flutter App'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final results = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    if (results.isEmpty) return null;
    final result = results.first as Map<String, dynamic>;
    final latitude = double.tryParse('${result['lat']}');
    final longitude = double.tryParse('${result['lon']}');
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  Future<void> _startTracking() async {
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      _shipper = LatLng(current.latitude, current.longitude);
      await _loadRoute();

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
            ),
          ).listen((position) {
            if (!mounted) return;
            setState(() {
              _shipper = LatLng(position.latitude, position.longitude);
            });
          });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
          _error = 'Không lấy được vị trí hiện tại của shipper.';
        });
      }
    }
  }

  Future<void> _loadRoute() async {
    final from = _shipper;
    if (from == null) return;
    setState(() {
      _loadingRoute = true;
      _error = null;
    });
    try {
      final path =
          '/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${_target.longitude},${_target.latitude}';
      final uri = Uri.https('router.project-osrm.org', path, {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception();
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final routes = data['routes'] as List;
      if (routes.isEmpty) throw Exception();
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final points = coordinates.map((coordinate) {
        final pair = coordinate as List;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      if (!mounted) return;
      setState(() {
        _route = points;
        _distanceKm = (route['distance'] as num).toDouble() / 1000;
        _durationMinutes = (route['duration'] as num).toDouble() / 60;
        _loadingRoute = false;
      });
      _fitRoute();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
          _error = 'Không tải được tuyến đường. Hãy thử lại.';
        });
      }
    }
  }

  void _fitRoute() {
    if (_route.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _route,
          padding: const EdgeInsets.fromLTRB(40, 80, 40, 250),
        ),
      );
    });
  }

  Future<void> _switchToDelivery() async {
    final shipper = _shipper;
    setState(() => _updatingStatus = true);
    try {
      await _shipperService.updateDeliveryStage(
        orderId: widget.order['id'] as int,
        status: 'DA_LAY_HANG',
        latitude: shipper?.latitude,
        longitude: shipper?.longitude,
      );
      if (!mounted) return;
      setState(() => _toReceiver = true);
      await _loadRoute();
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _completeDelivery() async {
    final shipper = _shipper;
    setState(() => _updatingStatus = true);
    try {
      await _shipperService.updateDeliveryStage(
        orderId: widget.order['id'] as int,
        status: 'DA_GIAO_HANG',
        latitude: shipper?.latitude,
        longitude: shipper?.longitude,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shipper = _shipper;
    final pickup = _pickup;
    final delivery = _delivery;
    if (pickup == null || delivery == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${widget.order['ma_van_don'] ?? 'Đơn hàng'}'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_off_outlined,
                        size: 52,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                    ],
                  ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.order['ma_van_don'] as String)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: shipper ?? pickup,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                  if (shipper != null)
                    _marker(shipper, Icons.delivery_dining, Colors.blue),
                  _marker(pickup, Icons.inventory_2, Colors.orange),
                  _marker(delivery, Icons.flag, Colors.red),
                ],
              ),
            ],
          ),
          if (_loadingRoute)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            ),
          Positioned(left: 16, right: 16, bottom: 16, child: _deliveryCard()),
        ],
      ),
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color) => Marker(
    point: point,
    width: 48,
    height: 48,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Icon(icon, color: Colors.white),
    ),
  );

  Widget _deliveryCard() {
    final address = _toReceiver
        ? widget.order['nguoi_nhan_dia_chi'] as String
        : widget.order['nguoi_gui_dia_chi'] as String;
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _toReceiver ? 'Đang giao tới người nhận' : 'Đang đến lấy hàng',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(address, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (_distanceKm != null && _durationMinutes != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_distanceKm!.toStringAsFixed(1)} km • '
                '${_durationMinutes!.ceil()} phút',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loadingRoute || _updatingStatus
                    ? null
                    : _toReceiver
                    ? _completeDelivery
                    : _switchToDelivery,
                icon: Icon(_toReceiver ? Icons.check_circle : Icons.inventory),
                label: Text(_toReceiver ? 'Đã giao hàng' : 'Đã lấy hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
