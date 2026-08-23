import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../services/cloudinary_service.dart';
import '../../services/customer_auth_service.dart';
import '../../services/evidence_image_service.dart';
import '../../services/last_mile_staff_service.dart';

class PickupNavigationScreen extends StatefulWidget {
  const PickupNavigationScreen({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  State<PickupNavigationScreen> createState() => _PickupNavigationScreenState();
}

class _PickupNavigationScreenState extends State<PickupNavigationScreen> {
  final _mapController = MapController();
  final _service = LastMileStaffService();
  final _cloudinaryService = CloudinaryService();
  final _evidenceImageService = EvidenceImageService();
  final _imagePicker = ImagePicker();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _simulationTimer;
  LatLng? _current;
  LatLng? _destination;
  List<LatLng> _route = [];
  double? _distanceKm;
  double? _durationMinutes;
  bool _loading = true;
  bool _simulating = false;
  bool _usingSimulatedPosition = false;
  bool _preparingSimulation = false;
  bool _confirming = false;
  String? _error;
  String? _warehouseAddress;

  String get _address => '${widget.order['dia_chi'] ?? ''}';
  String get _phone => '${widget.order['so_dien_thoai'] ?? ''}';
  String get _employeeName =>
      '${CustomerAuthService.currentEmployee?['ho_ten'] ?? 'Nhân viên lấy hàng'}';

  double? get _metersToPickup {
    final current = _current;
    final destination = _destination;
    if (current == null || destination == null) return null;
    return Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      destination.latitude,
      destination.longitude,
    );
  }

  bool get _canCaptureEvidence => (_metersToPickup ?? double.infinity) <= 500;

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
    try {
      final permission = await _locationPermission();
      if (!permission) throw Exception('Cần cấp quyền vị trí để chỉ đường');
      final destination = await _pickupCoordinates();
      if (destination == null) {
        throw Exception(
          'Đơn hàng chưa có tọa độ điểm lấy. Vui lòng chọn lại địa chỉ lấy hàng.',
        );
      }
      final results = await Future.wait([
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ),
      ]);
      final position = results[0];
      _current = LatLng(position.latitude, position.longitude);
      _destination = destination;
      await _loadRoute();
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            ),
          ).listen((position) {
            if (!mounted || _simulating) return;
            _current = LatLng(position.latitude, position.longitude);
            _loadRoute(moveMap: false);
          });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<LatLng?> _pickupCoordinates() async {
    LatLng? parse(Map<String, dynamic> source) {
      final latitude = source['nguoi_gui_vi_do'];
      final longitude = source['nguoi_gui_kinh_do'];
      final lat = latitude is num
          ? latitude.toDouble()
          : double.tryParse('$latitude');
      final lon = longitude is num
          ? longitude.toDouble()
          : double.tryParse('$longitude');
      return lat == null || lon == null ? null : LatLng(lat, lon);
    }

    final fromTask = parse(widget.order);
    try {
      final id = (widget.order['id'] as num).toInt();
      final fromDatabase = await _service.pickupCoordinates(id);
      final warehouseAddress = '${fromDatabase?['kho_dia_chi'] ?? ''}'.trim();
      if (warehouseAddress.isNotEmpty) _warehouseAddress = warehouseAddress;
      final coordinates = fromDatabase == null ? null : parse(fromDatabase);
      _warehouseAddress ??= await _service.currentWarehouseAddress();
      if (fromTask != null || coordinates != null) {
        return fromTask ?? coordinates;
      }
    } catch (_) {
      // Địa chỉ vẫn được dùng làm phương án dự phòng cho đơn cũ.
    }
    if (_warehouseAddress == null) {
      try {
        _warehouseAddress = await _service.currentWarehouseAddress();
      } catch (_) {
        // RPC vẫn là nguồn chính nếu RLS không cho phép đọc trực tiếp kho.
      }
    }
    if (fromTask != null) return fromTask;
    return _geocode(_address);
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
      final photonUri = Uri.https('photon.komoot.io', '/api/', {
        'q': query,
        'limit': '1',
      });
      final response = await http
          .get(photonUri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final features = (body as Map<String, dynamic>)['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final geometry = (features.first as Map<String, dynamic>)['geometry'];
          final coordinates = (geometry as Map<String, dynamic>)['coordinates'];
          if (coordinates is List && coordinates.length >= 2) {
            return LatLng(
              (coordinates[1] as num).toDouble(),
              (coordinates[0] as num).toDouble(),
            );
          }
        }
      }
    } catch (_) {
      // Thử nhà cung cấp thứ hai bên dưới.
    }

    try {
      final nominatimUri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': query,
        'countrycodes': 'vn',
        'limit': '1',
      });
      final response = await http
          .get(nominatimUri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      if (list.isEmpty) return null;
      final item = list.first as Map<String, dynamic>;
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      return lat == null || lon == null ? null : LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadRoute({bool moveMap = true}) async {
    final current = _current;
    final destination = _destination;
    if (current == null || destination == null) return;
    final path =
        '/route/v1/driving/'
        '${current.longitude},${current.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri.https('router.project-osrm.org', path, {
      'overview': 'full',
      'geometries': 'geojson',
      'steps': 'true',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Không tải được tuyến đường');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final routes = (data as Map<String, dynamic>)['routes'] as List;
    if (routes.isEmpty) throw Exception('Không tìm thấy tuyến đường phù hợp');
    final route = routes.first as Map<String, dynamic>;
    final coordinates =
        ((route['geometry'] as Map<String, dynamic>)['coordinates'] as List)
            .map((point) {
              final values = point as List;
              return LatLng(
                (values[1] as num).toDouble(),
                (values[0] as num).toDouble(),
              );
            })
            .toList();
    if (!mounted) return;
    setState(() {
      _route = coordinates;
      _distanceKm = (route['distance'] as num).toDouble() / 1000;
      _durationMinutes = (route['duration'] as num).toDouble() / 60;
      _loading = false;
      _error = null;
    });
    if (moveMap && coordinates.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: coordinates,
            padding: const EdgeInsets.fromLTRB(42, 130, 42, 330),
          ),
        );
      });
    }
  }

  Future<void> _toggleSimulation() async {
    if (_simulating) {
      _simulationTimer?.cancel();
      setState(() {
        _simulating = false;
        _usingSimulatedPosition = false;
      });
      return;
    }
    if (_preparingSimulation) return;
    final warehouseAddress = _warehouseAddress;
    if (warehouseAddress == null || warehouseAddress.isEmpty) {
      _showMessage('Chưa lấy được địa chỉ kho cấp 2 của nhân viên');
      return;
    }
    setState(() => _preparingSimulation = true);
    _usingSimulatedPosition = true;
    final warehouse = await _geocode(warehouseAddress);
    if (!mounted) return;
    if (warehouse == null) {
      setState(() => _preparingSimulation = false);
      _showMessage('Không tìm thấy tọa độ kho cấp 2 để bắt đầu giả lập');
      return;
    }
    try {
      _current = warehouse;
      await _loadRoute();
    } catch (error) {
      if (!mounted) return;
      setState(() => _preparingSimulation = false);
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    setState(() => _preparingSimulation = false);
    if (_route.length < 2) return;
    var index = 0;
    final originalDistance = _distanceKm ?? 0;
    final originalDuration = _durationMinutes ?? 0;
    final fullRoute = List<LatLng>.from(_route);
    const maximumSimulationSteps = 70;
    final step = (fullRoute.length / maximumSimulationSteps).ceil();
    final points = <LatLng>[
      for (var index = 0; index < fullRoute.length; index += step)
        fullRoute[index],
      if (fullRoute.last != _destination) _destination!,
    ];
    setState(() => _simulating = true);
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 550), (
      timer,
    ) {
      index++;
      if (!mounted || index >= points.length) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _simulating = false;
            _usingSimulatedPosition = true;
            _current = _destination;
            _route = [_destination!];
            _distanceKm = 0;
            _durationMinutes = 0;
          });
        }
        return;
      }
      final remainingRatio = (points.length - index - 1) / (points.length - 1);
      setState(() {
        _current = points[index];
        _route = points.sublist(index);
        _distanceKm = originalDistance * remainingRatio;
        _durationMinutes = originalDuration * remainingRatio;
      });
      _mapController.move(points[index], 16);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmPickedUp() async {
    final destination = _destination;
    if (destination == null) {
      _showMessage('Chưa có tọa độ điểm lấy hàng');
      return;
    }
    setState(() => _confirming = true);
    try {
      final evidencePosition = await _evidencePosition();
      final distanceMeters = Geolocator.distanceBetween(
        evidencePosition.latitude,
        evidencePosition.longitude,
        destination.latitude,
        destination.longitude,
      );
      if (distanceMeters > 500) {
        throw Exception(
          'Bạn còn cách điểm lấy ${distanceMeters.round()} m. Chỉ được chụp minh chứng trong phạm vi 500 m.',
        );
      }
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (image == null) return;
      final orderId = (widget.order['id'] as num).toInt();
      final trackingCode = '${widget.order['ma_van_don']}';
      final stampedImage = await _evidenceImageService.stamp(
        sourceBytes: await image.readAsBytes(),
        orderId: orderId,
        trackingCode: trackingCode,
        evidenceLabel: 'XÁC NHẬN NHÂN VIÊN ĐÃ LẤY HÀNG',
        employeeName: _employeeName,
        address: _address,
        latitude: evidencePosition.latitude,
        longitude: evidencePosition.longitude,
        capturedAt: DateTime.now(),
      );
      final evidenceUrl = await _cloudinaryService.uploadEvidence(
        imageBytes: stampedImage,
        trackingCode: trackingCode,
        evidenceType: 'pickup_staff_evidence',
        orderId: orderId,
        address: _address,
        latitude: evidencePosition.latitude,
        longitude: evidencePosition.longitude,
      );
      await _service.confirmPickupWithEvidence(
        orderId: orderId,
        evidenceUrl: evidenceUrl,
        latitude: evidencePosition.latitude,
        longitude: evidencePosition.longitude,
        pickupLatitude: destination.latitude,
        pickupLongitude: destination.longitude,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on CloudinaryUploadException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<LatLng> _evidencePosition() async {
    if (_usingSimulatedPosition && _current != null) return _current!;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.order['ma_van_don']}')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 58),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _prepare();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          )
        : Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: _current!, initialZoom: 15),
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
                        point: _destination!,
                        width: 54,
                        height: 54,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 48,
                        ),
                      ),
                      Marker(
                        point: _current!,
                        width: 54,
                        height: 54,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Card(
                  color: const Color(0xFF1769E0),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.navigation, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Đi theo tuyến đường đến điểm lấy hàng',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Còn ${(_distanceKm ?? 0).toStringAsFixed(1)} km',
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
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Đang đến lấy hàng',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(_address),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${(_distanceKm ?? 0).toStringAsFixed(1)} km • ${(_durationMinutes ?? 0).ceil()} phút',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: 'Gọi người gửi',
                              onPressed: _phone.isEmpty
                                  ? null
                                  : () => launchUrl(
                                      Uri(scheme: 'tel', path: _phone),
                                    ),
                              icon: const Icon(Icons.call),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: _preparingSimulation
                              ? null
                              : _toggleSimulation,
                          icon: Icon(
                            _preparingSimulation
                                ? Icons.hourglass_top
                                : _simulating
                                ? Icons.pause_circle
                                : Icons.play_circle,
                          ),
                          label: Text(
                            _preparingSimulation
                                ? 'Đang tạo tuyến từ kho cấp 2...'
                                : _simulating
                                ? 'Dừng giả lập'
                                : 'Giả lập từ kho cấp 2',
                          ),
                        ),
                        const SizedBox(height: 6),
                        FilledButton.icon(
                          onPressed: _confirming ? null : _confirmPickedUp,
                          icon: Icon(
                            _canCaptureEvidence
                                ? Icons.camera_alt_outlined
                                : Icons.location_searching,
                          ),
                          label: Text(
                            _confirming
                                ? 'Đang lưu minh chứng...'
                                : 'Xác nhận lấy hàng',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
