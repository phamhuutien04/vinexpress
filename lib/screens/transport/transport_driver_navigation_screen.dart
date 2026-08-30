import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../services/transport_driver_service.dart';
import '../../widgets/vietnam_island_markers.dart';

class TransportDriverNavigationScreen extends StatefulWidget {
  const TransportDriverNavigationScreen({
    super.key,
    required this.trip,
    required this.stage,
  });

  final Map<String, dynamic> trip;
  final Map<String, dynamic> stage;

  @override
  State<TransportDriverNavigationScreen> createState() =>
      _TransportDriverNavigationScreenState();
}

class _TransportDriverNavigationScreenState
    extends State<TransportDriverNavigationScreen> {
  final _mapController = MapController();
  final _driverService = TransportDriverService();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _simulationTimer;
  LatLng? _current;
  LatLng? _latestGps;
  LatLng? _destination;
  LatLng? _lastRouteOrigin;
  List<LatLng> _route = [];
  double? _distanceKm;
  double? _durationMinutes;
  DateTime? _lastRouteAt;
  DateTime? _lastLocationSyncAt;
  LatLng? _lastSyncedLocation;
  bool _loading = true;
  bool _routing = false;
  bool _simulationMode = false;
  bool _simulating = false;
  bool _preparingSimulation = false;
  String? _error;

  String get _warehouseName =>
      '${widget.stage['kho_den_ten'] ?? 'Kho tiếp theo'}';
  String get _warehouseAddress =>
      '${widget.stage['kho_den_dia_chi'] ?? _warehouseName}'.trim();
  String get _warehousePhone =>
      '${widget.stage['kho_den_so_dien_thoai'] ?? ''}'.trim();
  String get _originName => '${widget.stage['kho_di_ten'] ?? 'Kho xuất phát'}';
  String get _originAddress =>
      '${widget.stage['kho_di_dia_chi'] ?? _originName}'.trim();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (!await _locationPermission()) {
        throw Exception('Cần bật GPS và cấp quyền vị trí để chỉ đường');
      }
      final destination = await _geocode(_warehouseAddress);
      if (destination == null) {
        throw Exception('Không tìm thấy vị trí của kho trên OpenMap');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      _current = LatLng(position.latitude, position.longitude);
      if (!_isInVietnam(_current!)) {
        throw Exception('Vị trí GPS hiện tại nằm ngoài phạm vi Việt Nam');
      }
      _latestGps = _current;
      await _syncLocation(_current!, accuracyMeters: position.accuracy);
      _destination = destination;
      await _loadRoute();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen(_onPositionChanged);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _locationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<LatLng?> _geocode(String address) async {
    final query = '$address, Việt Nam';
    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': query,
        'limit': '1',
      });
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final features = (data as Map<String, dynamic>)['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final feature = Map<String, dynamic>.from(features.first as Map);
          final geometry = Map<String, dynamic>.from(
            feature['geometry'] as Map,
          );
          final coordinates = geometry['coordinates'] as List;
          final result = LatLng(
            (coordinates[1] as num).toDouble(),
            (coordinates[0] as num).toDouble(),
          );
          if (_isInVietnam(result)) return result;
        }
      }
    } catch (_) {
      // Thử nguồn OpenStreetMap dự phòng bên dưới.
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': query,
        'countrycodes': 'vn',
        'limit': '1',
      });
      final response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'VinExpress/1.0 com.vinexpress.app',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      if (data.isEmpty) return null;
      final item = Map<String, dynamic>.from(data.first as Map);
      final latitude = double.tryParse('${item['lat']}');
      final longitude = double.tryParse('${item['lon']}');
      if (latitude == null || longitude == null) return null;
      final result = LatLng(latitude, longitude);
      return _isInVietnam(result) ? result : null;
    } catch (_) {
      return null;
    }
  }

  bool _isInVietnam(LatLng point) =>
      point.latitude >= 8 &&
      point.latitude <= 24 &&
      point.longitude >= 102 &&
      point.longitude <= 110;

  Future<void> _loadRoute({bool moveMap = true}) async {
    final current = _current;
    final destination = _destination;
    if (current == null || destination == null || _routing) return;
    _routing = true;
    try {
      final vietnamPoints = _vietnamRoadPoints(current, destination);
      final coordinatePath = vietnamPoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final path =
          '/route/v1/driving/'
          '$coordinatePath';
      final uri = Uri.https('router.project-osrm.org', path, {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
      });
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) {
        throw Exception('Không tải được tuyến đường OpenMap');
      }
      final data = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        throw Exception('Không tìm thấy tuyến đường phù hợp');
      }
      final route = Map<String, dynamic>.from(routes.first as Map);
      final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
      final coordinates = (geometry['coordinates'] as List).map((point) {
        final values = point as List;
        return LatLng(
          (values[1] as num).toDouble(),
          (values[0] as num).toDouble(),
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _route = coordinates;
        _distanceKm = (route['distance'] as num).toDouble() / 1000;
        _durationMinutes = (route['duration'] as num).toDouble() / 60;
        _loading = false;
        _error = null;
        _lastRouteAt = DateTime.now();
        _lastRouteOrigin = current;
      });
      if (moveMap) _fitRoute();
    } finally {
      _routing = false;
    }
  }

  void _onPositionChanged(Position position) {
    if (!mounted) return;
    final next = LatLng(position.latitude, position.longitude);
    if (!_isInVietnam(next)) return;
    _latestGps = next;
    _syncLocation(next, accuracyMeters: position.accuracy);
    if (_simulationMode) return;
    setState(() => _current = next);
    final previous = _lastRouteOrigin;
    final elapsed = DateTime.now().difference(
      _lastRouteAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    final movedMeters = previous == null
        ? double.infinity
        : Geolocator.distanceBetween(
            previous.latitude,
            previous.longitude,
            next.latitude,
            next.longitude,
          );
    if (elapsed >= const Duration(seconds: 25) && movedMeters >= 80) {
      _loadRoute(moveMap: false).catchError((_) {});
    } else {
      _mapController.move(next, _mapController.camera.zoom);
    }
  }

  Future<void> _syncLocation(
    LatLng position, {
    double? accuracyMeters,
    bool force = false,
  }) async {
    final previous = _lastSyncedLocation;
    final elapsed = DateTime.now().difference(
      _lastLocationSyncAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    final movedMeters = previous == null
        ? double.infinity
        : Geolocator.distanceBetween(
            previous.latitude,
            previous.longitude,
            position.latitude,
            position.longitude,
          );
    if (!force && elapsed < const Duration(seconds: 8) && movedMeters < 40) {
      return;
    }
    try {
      await _driverService.updateLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: accuracyMeters,
      );
      _lastLocationSyncAt = DateTime.now();
      _lastSyncedLocation = position;
    } catch (_) {
      // Mất mạng tạm thời không được làm gián đoạn màn hình chỉ đường.
    }
  }

  List<LatLng> _vietnamRoadPoints(LatLng from, LatLng to) {
    final directDistanceKm =
        Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000;
    if (directDistanceKm < 280) return [from, to];

    const northSouthCorridor = <LatLng>[
      LatLng(10.7769, 106.7009), // Thành phố Hồ Chí Minh
      LatLng(10.9265, 107.2453), // Long Khánh
      LatLng(10.9805, 108.2615), // Phan Thiết
      LatLng(11.5826, 108.9912), // Phan Rang
      LatLng(12.2388, 109.1967), // Nha Trang
      LatLng(13.0882, 109.0929), // Tuy Hòa
      LatLng(13.7820, 109.2194), // Quy Nhơn
      LatLng(15.1214, 108.8044), // Quảng Ngãi
      LatLng(16.0544, 108.2022), // Đà Nẵng
      LatLng(16.4637, 107.5909), // Huế
      LatLng(17.4689, 106.6223), // Đồng Hới
      LatLng(18.3428, 105.9057), // Hà Tĩnh
      LatLng(18.6796, 105.6813), // Vinh
      LatLng(19.8067, 105.7852), // Thanh Hóa
      LatLng(20.2506, 105.9745), // Ninh Bình
      LatLng(21.0285, 105.8542), // Hà Nội
    ];

    final southToNorth = to.latitude >= from.latitude;
    final minimumLatitude = from.latitude < to.latitude
        ? from.latitude
        : to.latitude;
    final maximumLatitude = from.latitude > to.latitude
        ? from.latitude
        : to.latitude;
    final corridor = northSouthCorridor
        .where(
          (point) =>
              point.latitude > minimumLatitude + 0.12 &&
              point.latitude < maximumLatitude - 0.12,
        )
        .toList();
    final orderedCorridor = southToNorth
        ? corridor
        : corridor.reversed.toList();

    // Với hành trình dài ở miền Bắc hoặc miền Nam, đưa tuyến qua đầu mối
    // nội địa thay vì để bộ định tuyến cắt qua biên giới nước láng giềng.
    if (orderedCorridor.isEmpty && directDistanceKm >= 280) {
      if (from.latitude >= 19.5 && to.latitude >= 19.5) {
        orderedCorridor.add(const LatLng(21.0285, 105.8542));
      } else if (from.latitude <= 12 && to.latitude <= 12) {
        orderedCorridor.add(const LatLng(10.7769, 106.7009));
      }
    }
    return [from, ...orderedCorridor, to];
  }

  Future<void> _toggleSimulation() async {
    if (_preparingSimulation) return;
    if (_simulationMode) {
      await _stopSimulation();
      return;
    }
    setState(() => _preparingSimulation = true);
    try {
      final origin = await _geocode(_originAddress);
      if (origin == null) {
        throw Exception('Không tìm thấy vị trí kho xuất phát trên OpenMap');
      }
      if (!mounted) return;
      _simulationTimer?.cancel();
      setState(() {
        _simulationMode = true;
        _simulating = false;
        _current = origin;
      });
      await _loadRoute();
      if (!mounted || _route.length < 2) return;
      _startSimulationMovement();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _simulationMode = false;
        _simulating = false;
      });
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _preparingSimulation = false);
    }
  }

  void _startSimulationMovement() {
    final fullRoute = List<LatLng>.from(_route);
    if (fullRoute.length < 2) return;
    final originalDistance = _distanceKm ?? 0;
    final originalDuration = _durationMinutes ?? 0;
    const maximumSteps = 90;
    final step = (fullRoute.length / maximumSteps).ceil();
    final points = <LatLng>[
      for (var index = 0; index < fullRoute.length; index += step)
        fullRoute[index],
      if (fullRoute.last != _destination) _destination!,
    ];
    var index = 0;
    setState(() {
      _simulating = true;
      _current = points.first;
    });
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 550), (
      timer,
    ) {
      index++;
      if (!mounted || index >= points.length) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _simulating = false;
            _current = _destination;
            _distanceKm = 0;
            _durationMinutes = 0;
          });
          _mapController.move(_destination!, 16);
        }
        return;
      }
      final remainingRatio = (points.length - index - 1) / (points.length - 1);
      setState(() {
        _current = points[index];
        _distanceKm = originalDistance * remainingRatio;
        _durationMinutes = originalDuration * remainingRatio;
      });
      _syncLocation(points[index]);
      _mapController.move(points[index], 16);
    });
  }

  Future<void> _stopSimulation() async {
    _simulationTimer?.cancel();
    var gps = _latestGps;
    if (gps == null) {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      gps = LatLng(position.latitude, position.longitude);
      _latestGps = gps;
    }
    if (!mounted) return;
    setState(() {
      _simulationMode = false;
      _simulating = false;
      _current = gps;
    });
    try {
      await _loadRoute();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _fitRoute() {
    if (_route.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _route.isEmpty) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _route,
          padding: const EdgeInsets.fromLTRB(38, 145, 38, 285),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.trip['ma_chuyen']}')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _NavigationError(message: _error!, onRetry: _prepare)
        : Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: _current!, initialZoom: 15),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.vinexpress.app',
                    maxZoom: 19,
                  ),
                  if (_route.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _route,
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
                      _mapMarker(
                        _destination!,
                        Icons.warehouse_rounded,
                        AppColors.error,
                      ),
                      _mapMarker(
                        _current!,
                        Icons.local_shipping_rounded,
                        AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: _NavigationBanner(
                    warehouseName: _warehouseName,
                    distanceKm: _distanceKm,
                    simulationMode: _simulationMode,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 320,
                child: FloatingActionButton.small(
                  heroTag: 'fit_transport_route',
                  tooltip: 'Xem toàn tuyến',
                  onPressed: _fitRoute,
                  child: const Icon(Icons.center_focus_strong_rounded),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _WarehouseNavigationCard(
                  name: _warehouseName,
                  address: _warehouseAddress,
                  phone: _warehousePhone,
                  distanceKm: _distanceKm,
                  durationMinutes: _durationMinutes,
                  simulationMode: _simulationMode,
                  simulating: _simulating,
                  preparingSimulation: _preparingSimulation,
                  originName: _originName,
                  onToggleSimulation: _toggleSimulation,
                ),
              ),
            ],
          ),
  );

  Marker _mapMarker(LatLng point, IconData icon, Color color) => Marker(
    point: point,
    width: 50,
    height: 50,
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
}

class _NavigationBanner extends StatelessWidget {
  const _NavigationBanner({
    required this.warehouseName,
    required this.distanceKm,
    required this.simulationMode,
  });

  final String warehouseName;
  final double? distanceKm;
  final bool simulationMode;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFF1769E0),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 6)),
      ],
    ),
    child: Row(
      children: [
        const Icon(Icons.navigation_rounded, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đi tới $warehouseName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                simulationMode
                    ? 'Giả lập nội địa Việt Nam  |  Tuyến cố định'
                    : distanceKm == null
                    ? 'GPS thật  |  Đang tính tuyến nội địa Việt Nam'
                    : 'GPS thật  |  Tuyến nội địa Việt Nam  |  Còn ${distanceKm!.toStringAsFixed(1)} km',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WarehouseNavigationCard extends StatelessWidget {
  const _WarehouseNavigationCard({
    required this.name,
    required this.address,
    required this.phone,
    required this.distanceKm,
    required this.durationMinutes,
    required this.simulationMode,
    required this.simulating,
    required this.preparingSimulation,
    required this.originName,
    required this.onToggleSimulation,
  });

  final String name;
  final String address;
  final String phone;
  final double? distanceKm;
  final double? durationMinutes;
  final bool simulationMode;
  final bool simulating;
  final bool preparingSimulation;
  final String originName;
  final VoidCallback onToggleSimulation;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 8,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary10,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.warehouse_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(address, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                IconButton.filled(
                  tooltip: 'Gọi kho',
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                  icon: const Icon(Icons.call_rounded),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.route_rounded,
                  label: 'Quãng đường',
                  value: distanceKm == null
                      ? 'Đang tính'
                      : '${distanceKm!.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  icon: Icons.schedule_rounded,
                  label: 'Dự kiến',
                  value: durationMinutes == null
                      ? 'Đang tính'
                      : '${durationMinutes!.ceil()} phút',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: preparingSimulation ? null : onToggleSimulation,
              icon: Icon(
                preparingSimulation
                    ? Icons.hourglass_top_rounded
                    : simulationMode
                    ? Icons.gps_fixed_rounded
                    : Icons.play_circle_outline_rounded,
              ),
              label: Text(
                preparingSimulation
                    ? 'Đang tạo tuyến giả lập'
                    : simulationMode
                    ? 'Trở về GPS thật'
                    : 'Giả lập từ $originName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (simulationMode) ...[
            const SizedBox(height: 7),
            Text(
              simulating
                  ? 'Xe mô phỏng đang chạy trên tuyến cố định.'
                  : 'Giả lập đã đến kho. Tuyến vẫn được giữ cố định.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NavigationError extends StatelessWidget {
  const _NavigationError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_off_outlined,
            size: 58,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}
