import 'dart:async';

import 'package:flutter/foundation.dart';
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

  Future<bool> getReceivingStatus() async {
    try {
      return await _client.rpc('trang_thai_nhan_don_shipper') as bool;
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> setReceivingStatus(bool enabled) async {
    try {
      await _client.rpc(
        'cap_nhat_trang_thai_nhan_don_shipper',
        params: {'p_san_sang': enabled},
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> updateTrackingLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    try {
      await _client.rpc(
        'cap_nhat_vi_tri_shipper',
        params: {
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
          'p_do_chinh_xac_met': accuracyMeters,
        },
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<Position> updateCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ShipperServiceException(
          'Vui lòng bật GPS trên điện thoại.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ShipperServiceException(
          'Edge chưa được cấp quyền vị trí. Hãy chọn Cho phép rồi bấm cập nhật vị trí.',
        );
      }

      // Trình duyệt không hỗ trợ getLastKnownPosition. Nếu gọi trước trên web,
      // luồng sẽ lỗi ngay và không bao giờ kịp yêu cầu GPS hiện tại.
      // Trên ứng dụng điện thoại vẫn tận dụng vị trí gần nhất làm dự phòng.
      final Position? cachedPosition = kIsWeb
          ? null
          : await Geolocator.getLastKnownPosition();
      final cachedIsFresh =
          cachedPosition != null &&
          DateTime.now().difference(cachedPosition.timestamp).abs() <
              const Duration(minutes: 2);
      late final Position position;
      if (cachedIsFresh) {
        position = cachedPosition;
      } else {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              // GPS trên Edge di động thường cần lâu hơn lần đầu lấy tín hiệu.
              timeLimit: Duration(seconds: 15),
            ),
          ).timeout(const Duration(seconds: 18));
        } on TimeoutException {
          if (cachedPosition == null) {
            throw const ShipperServiceException(
              'Chưa lấy được tín hiệu GPS. Hãy ra nơi thoáng rồi bấm cập nhật vị trí.',
            );
          }
          position = cachedPosition;
        }
      }

      await updateTrackingLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      ).timeout(const Duration(seconds: 12));
      return position;
    } on ShipperServiceException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    } catch (error) {
      final detail = '$error'.toLowerCase();
      if (detail.contains('permission') || detail.contains('denied')) {
        throw const ShipperServiceException(
          'Edge chưa được cấp quyền vị trí. Hãy chọn Cho phép rồi bấm cập nhật vị trí.',
        );
      }
      if (detail.contains('secure context') ||
          detail.contains('secure origin') ||
          detail.contains('only secure origins') ||
          detail.contains('not secure')) {
        throw const ShipperServiceException(
          'Edge chưa lấy được GPS. Nếu đang mở app bằng địa chỉ IP http, hãy dùng bản ứng dụng điện thoại hoặc mở web qua HTTPS.',
        );
      }
      if (detail.contains('timeout')) {
        throw const ShipperServiceException(
          'GPS đang mất nhiều thời gian hơn bình thường. Hãy thử lại ở nơi thoáng hơn.',
        );
      }
      if (kIsWeb) {
        throw const ShipperServiceException(
          'Edge chưa trả về vị trí hiện tại. Hãy bấm cập nhật vị trí một lần nữa.',
        );
      }
      throw const ShipperServiceException(
        'Chưa lấy được vị trí. Hãy bật GPS, bật độ chính xác cao rồi thử lại.',
      );
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

  Future<List<Map<String, dynamic>>> getActiveOrders() async {
    try {
      final data = await _client.rpc('don_hang_dang_giao_cua_shipper');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<List<Map<String, dynamic>>> getDeliveredOrderHistory() async {
    try {
      final data = await _client.rpc('lich_su_don_hang_shipper');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<Map<String, dynamic>> getWalletInfo() async {
    try {
      final data = await _client.rpc('thong_tin_vi');
      final rows = List<Map<String, dynamic>>.from(data as List);
      return rows.isEmpty ? <String, dynamic>{} : rows.first;
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<List<Map<String, dynamic>>> getWalletTransactions() async {
    try {
      final data = await _client.rpc('lich_su_giao_dich_vi');
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<int> requestWalletTopUp(double amount) async {
    try {
      final data = await _client.rpc(
        'tao_yeu_cau_nap_vi',
        params: {'p_so_tien': amount, 'p_phuong_thuc': 'CHUYEN_KHOAN'},
      );
      return (data as num).toInt();
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<int> requestWalletWithdrawal({required double amount}) async {
    try {
      final data = await _client.rpc(
        'tao_yeu_cau_rut_vi',
        params: {'p_so_tien': amount},
      );
      return (data as num).toInt();
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> linkWalletBankAccount({
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    try {
      await _client.rpc(
        'lien_ket_tai_khoan_ngan_hang_vi',
        params: {
          'p_ngan_hang': bankName,
          'p_so_tai_khoan': accountNumber,
          'p_chu_tai_khoan': accountHolder,
        },
      );
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
    String? evidenceUrl,
  }) async {
    try {
      await _client.rpc(
        'cap_nhat_chang_giao_shipper',
        params: {
          'p_don_hang_id': orderId,
          'p_trang_thai_moi': status,
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
          'p_minh_chung': evidenceUrl,
        },
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> reportDeliveryFailed({
    required int orderId,
    required String reason,
    required String evidenceUrl,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _client.rpc(
        'shipper_bao_giao_that_bai',
        params: {
          'p_don_hang_id': orderId,
          'p_ly_do': reason,
          'p_minh_chung': evidenceUrl,
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
        },
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> reportPickupFailed({
    required int orderId,
    required String reason,
    required String evidenceUrl,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _client.rpc(
        'shipper_bao_khong_nhan_duoc_hang',
        params: {
          'p_don_hang_id': orderId,
          'p_ly_do': reason,
          'p_minh_chung': evidenceUrl,
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
        },
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }

  Future<void> confirmReturnedToSender({
    required int orderId,
    required String evidenceUrl,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _client.rpc(
        'shipper_xac_nhan_hoan_hang',
        params: {
          'p_don_hang_id': orderId,
          'p_minh_chung': evidenceUrl,
          'p_vi_do': latitude,
          'p_kinh_do': longitude,
        },
      );
    } on PostgrestException catch (error) {
      throw ShipperServiceException(error.message);
    }
  }
}
