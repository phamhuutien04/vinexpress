import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_colors.dart';
import '../../services/shipper_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/evidence_image_service.dart';

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
  final _cloudinaryService = CloudinaryService();
  final _evidenceImageService = EvidenceImageService();
  final _imagePicker = ImagePicker();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _simulationTimer;
  LatLng? _shipper;
  LatLng? _pickup;
  LatLng? _delivery;
  List<LatLng> _route = [];
  bool _toReceiver = false;
  bool _navigationStarted = false;
  bool _simulating = false;
  bool _simulatedThisStage = false;
  bool _loadingRoute = true;
  bool _updatingStatus = false;
  double? _distanceKm;
  double? _durationMinutes;
  String? _error;
  LatLng? _lastRouteOrigin;
  String _instruction = 'Đi thẳng theo tuyến đường';
  double? _nextTurnMeters;
  String? _turnModifier;

  LatLng get _target => (_toReceiver ? _delivery : _pickup)!;

  @override
  void initState() {
    super.initState();
    _toReceiver = const {
      'DA_LAY_HANG',
      'GIAO_CHO_SHIPPER',
      'DANG_GIAO_HANG',
    }.contains(widget.order['trang_thai']);
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
      setState(() {
        _shipper = LatLng(current.latitude, current.longitude);
        _loadingRoute = false;
      });

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
            ),
          ).listen((position) {
            if (!mounted) return;
            if (_simulating) return;
            final updatedPosition = LatLng(
              position.latitude,
              position.longitude,
            );
            setState(() {
              _shipper = updatedPosition;
            });
            if (_navigationStarted) {
              _mapController.move(updatedPosition, 17);
            }
            final lastOrigin = _lastRouteOrigin;
            if (_navigationStarted &&
                !_loadingRoute &&
                (lastOrigin == null ||
                    const Distance().as(
                          LengthUnit.Meter,
                          lastOrigin,
                          updatedPosition,
                        ) >=
                        50)) {
              unawaited(_loadRoute());
            }
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
      final legs = route['legs'] as List?;
      final steps = legs == null || legs.isEmpty
          ? const <dynamic>[]
          : ((legs.first as Map<String, dynamic>)['steps'] as List? ??
                const <dynamic>[]);
      final currentStep = steps.isEmpty
          ? null
          : Map<String, dynamic>.from(steps.first as Map);
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final points = coordinates.map((coordinate) {
        final pair = coordinate as List;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      if (!mounted) return;
      setState(() {
        _route = points;
        _lastRouteOrigin = from;
        _distanceKm = (route['distance'] as num).toDouble() / 1000;
        _durationMinutes = (route['duration'] as num).toDouble() / 60;
        if (currentStep != null) {
          final maneuver = Map<String, dynamic>.from(
            currentStep['maneuver'] as Map? ?? const {},
          );
          _turnModifier = maneuver['modifier'] as String?;
          _nextTurnMeters = (currentStep['distance'] as num?)?.toDouble();
          _instruction = _instructionForStep(currentStep, maneuver);
        }
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
    _stopSimulation();
    setState(() => _updatingStatus = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (image == null) return;
      final usingSimulation = _simulatedThisStage;
      final capturedPosition = await _evidencePosition();
      final stampedImage = await _evidenceImageService.stamp(
        sourceBytes: await image.readAsBytes(),
        orderId: widget.order['id'] as int,
        trackingCode: '${widget.order['ma_van_don']}',
        evidenceLabel: 'XÁC NHẬN ĐÃ LẤY HÀNG',
        address: '${widget.order['nguoi_gui_dia_chi']}',
        latitude: capturedPosition.latitude,
        longitude: capturedPosition.longitude,
        capturedAt: DateTime.now(),
        locationSource: usingSimulation ? 'GIẢ LẬP' : 'GPS THẬT',
      );
      final evidenceUrl = await _cloudinaryService.uploadEvidence(
        imageBytes: stampedImage,
        trackingCode: '${widget.order['ma_van_don']}',
        evidenceType: 'pickup_evidence',
        orderId: widget.order['id'] as int,
        address: '${widget.order['nguoi_gui_dia_chi']}',
        latitude: capturedPosition.latitude,
        longitude: capturedPosition.longitude,
        locationSource: usingSimulation ? 'simulation' : 'gps',
      );
      await _shipperService.updateDeliveryStage(
        orderId: widget.order['id'] as int,
        status: 'DA_LAY_HANG',
        latitude: capturedPosition.latitude,
        longitude: capturedPosition.longitude,
        evidenceUrl: evidenceUrl,
      );
      if (!mounted) return;
      setState(() {
        _toReceiver = true;
        _simulatedThisStage = false;
      });
      await _loadRoute();
    } on CloudinaryUploadException catch (error) {
      if (mounted) _showError(error.message);
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _startNavigation() async {
    if (_shipper == null) {
      _showError('Chưa lấy được vị trí hiện tại của shipper.');
      return;
    }
    setState(() => _navigationStarted = true);
    await _loadRoute();
  }

  Future<void> _toggleSimulation() async {
    if (_simulating) {
      _stopSimulation();
      return;
    }
    if (_route.length < 2) {
      setState(() => _navigationStarted = true);
      await _loadRoute();
    }
    if (!mounted || _route.length < 2) {
      _showError('Chưa có tuyến đường để giả lập.');
      return;
    }

    final simulationRoute = List<LatLng>.from(_route);
    var index = 0;
    final pointsPerTick = (simulationRoute.length / 120)
        .ceil()
        .clamp(1, 20)
        .toInt();
    setState(() {
      _navigationStarted = true;
      _simulating = true;
      _simulatedThisStage = true;
    });

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      index = (index + pointsPerTick)
          .clamp(0, simulationRoute.length - 1)
          .toInt();
      final remainingRoute = simulationRoute.sublist(index);
      final current = simulationRoute[index];
      final remainingMeters = _polylineMeters(remainingRoute);
      setState(() {
        _shipper = current;
        _route = remainingRoute;
        _distanceKm = remainingMeters / 1000;
        _durationMinutes = remainingMeters / 1000 / 25 * 60;
        _nextTurnMeters = remainingMeters;
        _instruction = remainingMeters < 80
            ? 'Sắp đến điểm đích'
            : 'Tiếp tục đi theo tuyến đường';
      });
      _mapController.move(current, 17);

      if (index >= simulationRoute.length - 1) {
        _stopSimulation(reachedDestination: true);
      }
    });
  }

  double _polylineMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var meters = 0.0;
    const distance = Distance();
    for (var index = 1; index < points.length; index++) {
      meters += distance.as(LengthUnit.Meter, points[index - 1], points[index]);
    }
    return meters;
  }

  void _stopSimulation({bool reachedDestination = false}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    if (!mounted) return;
    setState(() {
      _simulating = false;
      if (reachedDestination) {
        _distanceKm = 0;
        _durationMinutes = 0;
        _nextTurnMeters = 0;
        _instruction = 'Đã đến điểm đích';
      }
    });
    if (reachedDestination) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _toReceiver
                ? 'Giả lập đã đến địa chỉ người nhận'
                : 'Giả lập đã đến điểm lấy hàng',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  String _instructionForStep(
    Map<String, dynamic> step,
    Map<String, dynamic> maneuver,
  ) {
    final type = '${maneuver['type'] ?? ''}';
    final modifier = '${maneuver['modifier'] ?? ''}';
    final road = '${step['name'] ?? ''}'.trim();
    final roadText = road.isEmpty ? '' : ' vào $road';
    if (type == 'arrive') return 'Bạn sắp đến điểm đích';
    if (type == 'roundabout' || type == 'rotary') {
      return 'Đi vào vòng xuyến$roadText';
    }
    if (modifier.contains('left')) return 'Rẽ trái$roadText';
    if (modifier.contains('right')) return 'Rẽ phải$roadText';
    if (modifier == 'uturn') return 'Quay đầu$roadText';
    return road.isEmpty ? 'Đi thẳng theo tuyến đường' : 'Đi thẳng trên $road';
  }

  IconData get _turnIcon {
    final modifier = _turnModifier ?? '';
    if (modifier.contains('left')) return Icons.turn_left_rounded;
    if (modifier.contains('right')) return Icons.turn_right_rounded;
    if (modifier == 'uturn') return Icons.u_turn_left_rounded;
    return Icons.straight_rounded;
  }

  Future<void> _completeDelivery() async {
    setState(() => _updatingStatus = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (image == null) return;
      final usingSimulation = _simulatedThisStage;
      final capturedPosition = await _evidencePosition();
      final stampedImage = await _evidenceImageService.stamp(
        sourceBytes: await image.readAsBytes(),
        orderId: widget.order['id'] as int,
        trackingCode: '${widget.order['ma_van_don']}',
        evidenceLabel: 'XÁC NHẬN ĐÃ GIAO HÀNG',
        address: '${widget.order['nguoi_nhan_dia_chi']}',
        latitude: capturedPosition.latitude,
        longitude: capturedPosition.longitude,
        capturedAt: DateTime.now(),
        locationSource: usingSimulation ? 'GIẢ LẬP' : 'GPS THẬT',
      );
      final evidenceUrl = await _cloudinaryService.uploadEvidence(
        imageBytes: stampedImage,
        trackingCode: '${widget.order['ma_van_don']}',
        evidenceType: 'delivery_evidence',
        orderId: widget.order['id'] as int,
        address: '${widget.order['nguoi_nhan_dia_chi']}',
        latitude: capturedPosition.latitude,
        longitude: capturedPosition.longitude,
        locationSource: usingSimulation ? 'simulation' : 'gps',
      );
      await _shipperService.updateDeliveryStage(
        orderId: widget.order['id'] as int,
        status: 'DA_GIAO_HANG',
        latitude: capturedPosition.latitude,
        longitude: capturedPosition.longitude,
        evidenceUrl: evidenceUrl,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on CloudinaryUploadException catch (error) {
      if (mounted) _showError(error.message);
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<LatLng> _evidencePosition() async {
    if (_simulatedThisStage && _shipper != null) return _shipper!;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
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
          if (_navigationStarted)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Card(
                  color: const Color(0xFF1769E0),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(_turnIcon, color: Colors.white, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _instruction,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (_nextTurnMeters != null)
                                Text(
                                  _nextTurnMeters! >= 1000
                                      ? 'Còn ${(_nextTurnMeters! / 1000).toStringAsFixed(1)} km'
                                      : 'Còn ${_nextTurnMeters!.round()} m',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
              child: OutlinedButton.icon(
                onPressed: _loadingRoute ? null : _startNavigation,
                icon: Icon(
                  _navigationStarted
                      ? Icons.navigation_rounded
                      : Icons.directions_rounded,
                ),
                label: Text(
                  _navigationStarted
                      ? 'Cập nhật chỉ đường'
                      : 'Bắt đầu chỉ đường',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadingRoute ? null : _toggleSimulation,
                icon: Icon(
                  _simulating
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                label: Text(_simulating ? 'Dừng giả lập' : 'Giả lập di chuyển'),
              ),
            ),
            const SizedBox(height: 8),
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
