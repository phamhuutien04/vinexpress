import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

class ShipperServiceException implements Exception {
  const ShipperServiceException(this.message);
  final String message;
}

class ShipperService {
  ShipperService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  Future<Position> updateCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ShipperServiceException('Vui lòng bật GPS trên điện thoại.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const ShipperServiceException(
        'Bạn cần cấp quyền vị trí để nhận đơn gần mình.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    try {
      await _client.rpc(
        'cap_nhat_vi_tri_shipper',
        params: {
          'p_vi_do': position.latitude,
          'p_kinh_do': position.longitude,
          'p_do_chinh_xac_met': position.accuracy,
        },
      );
      return position;
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<List<Map<String, dynamic>>> getNearbyOrders({
    double radiusKm = 10,
  }) async {
    try {
      final data = await _client.rpc(
        'don_hang_gan_shipper',
        params: {'p_ban_kinh_km': radiusKm},
      );
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> acceptOrder(int orderId, {double radiusKm = 10}) async {
    try {
      await _client.rpc(
        'nhan_don_hang_gan',
        params: {'p_don_hang_id': orderId, 'p_ban_kinh_km': radiusKm},
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> rejectOrder(int orderId, {String? reason}) async {
    try {
      await _client.rpc(
        'tu_choi_don_hang_gan',
        params: {'p_don_hang_id': orderId, 'p_ly_do': reason},
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> updateDeliveryStage({
    required int orderId,
    required String status,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _client.rpc(
        'cap_nhat_chang_giao_shipper',
        params: {
          'p_don_hang_id': orderId,
          'p_trang_thai_moi': status,
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
        },
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }
}
