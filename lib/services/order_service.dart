import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

class OrderServiceException implements Exception {
  const OrderServiceException(this.message);
  final String message;
}

class OrderQuote {
  const OrderQuote({
    required this.distanceKm,
    required this.shippingFee,
    required this.vehicle,
  });

  final double distanceKm;
  final double shippingFee;
  final String vehicle;
}

class OrderService {
  OrderService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  static const double directPricePerKm = 5000;

  Future<List<Map<String, dynamic>>> getCustomerOrders() async {
    try {
      final data = await _client.rpc('don_hang_cua_khach_hang');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw OrderServiceException(error.message);
    }
  }

  Future<Map<String, dynamic>> getCustomerOrderTracking(int orderId) async {
    try {
      final data = await _client
          .rpc(
            'theo_doi_don_hang_khach_hang',
            params: {'p_don_hang_id': orderId},
          )
          .single();
      return Map<String, dynamic>.from(data);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' ||
          error.message.contains('theo_doi_don_hang_khach_hang')) {
        throw const OrderServiceException(
          'Chức năng theo dõi chưa được cài trên Supabase. '
          'Hãy chạy file customer_tracking_setup.sql.',
        );
      }
      throw OrderServiceException(error.message);
    }
  }

  Future<void> cancelCustomerOrder({
    required int orderId,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'huy_don_hang_khach_hang',
        params: {
          'p_don_hang_id': orderId,
          'p_ly_do': reason?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw OrderServiceException(error.message);
    }
  }

  Future<void> rateDeliveredOrder({
    required int orderId,
    required int stars,
    String? comment,
  }) async {
    try {
      await _client.rpc(
        'danh_gia_shipper_don_hang',
        params: {
          'p_don_hang_id': orderId,
          'p_diem': stars,
          'p_binh_luan': comment?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw OrderServiceException(error.message);
    }
  }

  Future<OrderQuote> calculateShippingQuote({
    required String senderAddress,
    required String receiverAddress,
    double? senderLatitude,
    double? senderLongitude,
  }) async {
    final route = await _calculateRoute(
      senderAddress,
      receiverAddress,
      senderCoordinates: senderLatitude != null && senderLongitude != null
          ? _Coordinates(latitude: senderLatitude, longitude: senderLongitude)
          : null,
    );
    final direct = route.distanceKm <= 50;
    final fee = await _directShippingFee(route.distanceKm);
    return OrderQuote(
      distanceKm: route.distanceKm,
      shippingFee: fee,
      vehicle: direct ? 'XE_MAY' : 'XE_TAI',
    );
  }

  Future<Map<String, dynamic>> createOrder({
    required String senderName,
    required String senderPhone,
    required String senderAddress,
    required String receiverName,
    required String receiverPhone,
    required String receiverAddress,
    required double weight,
    required double itemValue,
    required double shippingFee,
    required double cod,
    double? senderLatitude,
    double? senderLongitude,
    String? note,
  }) async {
    try {
      final route = await _calculateRoute(
        senderAddress,
        receiverAddress,
        senderCoordinates: senderLatitude != null && senderLongitude != null
            ? _Coordinates(latitude: senderLatitude, longitude: senderLongitude)
            : null,
      );
      final calculatedShippingFee = await _directShippingFee(route.distanceKm);
      final data = await _client
          .rpc(
            'tao_don_hang_khach_hang',
            params: {
              'p_nguoi_gui_ten': senderName.trim(),
              'p_nguoi_gui_dia_chi': senderAddress.trim(),
              'p_nguoi_gui_sdt': _normalizePhone(senderPhone),
              'p_nguoi_nhan_ten': receiverName.trim(),
              'p_nguoi_nhan_dia_chi': receiverAddress.trim(),
              'p_nguoi_nhan_sdt': _normalizePhone(receiverPhone),
              'p_can_nang': weight,
              'p_gia_tri_hang': itemValue,
              'p_phi_van_chuyen': calculatedShippingFee,
              'p_cod': cod,
              'p_khoang_cach_km': route.distanceKm,
              'p_nguoi_gui_vi_do': route.sender.latitude,
              'p_nguoi_gui_kinh_do': route.sender.longitude,
              'p_nguoi_nhan_vi_do': route.receiver.latitude,
              'p_nguoi_nhan_kinh_do': route.receiver.longitude,
              'p_ghi_chu': note?.trim(),
            },
          )
          .single();
      final order = Map<String, dynamic>.from(data);
      order.addAll({
        'nguoi_gui_ten': senderName.trim(),
        'nguoi_gui_dia_chi': senderAddress.trim(),
        'nguoi_gui_sdt': _normalizePhone(senderPhone),
        'nguoi_nhan_ten': receiverName.trim(),
        'nguoi_nhan_dia_chi': receiverAddress.trim(),
        'nguoi_nhan_sdt': _normalizePhone(receiverPhone),
        'can_nang': weight,
        'gia_tri_hang': itemValue,
        'phi_van_chuyen':
            (order['phi_van_chuyen'] as num?)?.toDouble() ??
            calculatedShippingFee,
        'cod': cod,
        'ghi_chu': note?.trim(),
      });
      return order;
    } on OrderServiceException {
      rethrow;
    } on PostgrestException catch (error) {
      throw OrderServiceException(error.message);
    } catch (_) {
      throw const OrderServiceException(
        'Không thể kết nối máy chủ. Vui lòng thử lại.',
      );
    }
  }

  String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<double> _directShippingFee(double distanceKm) async {
    var pricePerKm = directPricePerKm;
    try {
      final data = await _client.rpc('lay_phi_van_chuyen_xe_may').single();
      pricePerKm = (data['phi_van_chuyen'] as num).toDouble();
    } on PostgrestException {
      // Dùng mức mặc định trong lúc database chưa chạy migration cấu hình phí.
    }
    return (distanceKm * pricePerKm).roundToDouble();
  }

  Future<_DeliveryRoute> _calculateRoute(
    String senderAddress,
    String receiverAddress, {
    _Coordinates? senderCoordinates,
  }) async {
    final sender =
        senderCoordinates ?? await _coordinatesForAddress(senderAddress);
    final receiver = await _coordinatesForAddress(receiverAddress);
    final meters = await _roadDistanceMeters(sender, receiver);
    final distanceKm = double.parse((meters / 1000).toStringAsFixed(2));
    return _DeliveryRoute(
      distanceKm: distanceKm,
      sender: sender,
      receiver: receiver,
    );
  }

  Future<double> _roadDistanceMeters(
    _Coordinates sender,
    _Coordinates receiver,
  ) async {
    final path =
        '/route/v1/driving/${sender.longitude},${sender.latitude};'
        '${receiver.longitude},${receiver.latitude}';
    final uri = Uri.https('router.project-osrm.org', path, {
      'overview': 'false',
      'alternatives': 'false',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const OrderServiceException(
        'Không thể tính quãng đường giao hàng.',
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final routes = (data as Map<String, dynamic>)['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw const OrderServiceException(
        'Không tìm thấy tuyến đường giữa hai địa chỉ.',
      );
    }
    return (routes.first['distance'] as num).toDouble();
  }

  Future<_Coordinates> _coordinatesForAddress(String address) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': '$address, Việt Nam',
      'countrycodes': 'vn',
      'limit': '1',
    });
    final response = await http
        .get(uri, headers: const {'User-Agent': 'VinExpress Flutter App'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const OrderServiceException(
        'Không thể tính khoảng cách giao hàng.',
      );
    }
    final results = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    if (results.isEmpty) {
      throw OrderServiceException(
        'Không tìm thấy tọa độ của địa chỉ: $address',
      );
    }
    final first = Map<String, dynamic>.from(results.first as Map);
    return _Coordinates(
      latitude: double.parse(first['lat'] as String),
      longitude: double.parse(first['lon'] as String),
    );
  }
}

class _Coordinates {
  const _Coordinates({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

class _DeliveryRoute {
  const _DeliveryRoute({
    required this.distanceKm,
    required this.sender,
    required this.receiver,
  });
  final double distanceKm;
  final _Coordinates sender;
  final _Coordinates receiver;
}
