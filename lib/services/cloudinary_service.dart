import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/config/cloudinary_config.dart';

class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(this.message);
  final String message;
}

class CloudinaryService {
  Future<String> uploadEvidence({
    required Uint8List imageBytes,
    required String trackingCode,
    required String evidenceType,
    required int orderId,
    required String address,
    required double latitude,
    required double longitude,
    required String locationSource,
  }) async {
    final safeAddress = address.replaceAll('|', ' ').replaceAll('=', '-');
    final request =
        http.MultipartRequest('POST', CloudinaryConfig.imageUploadUri)
          ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
          ..fields['context'] =
              'order_id=$orderId|tracking_code=$trackingCode|type=$evidenceType|'
              'latitude=$latitude|longitude=$longitude|address=$safeAddress'
              '|location_source=$locationSource'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              imageBytes,
              filename: '${trackingCode}_$evidenceType.png',
            ),
          );

    final response = await request.send().timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final cloudinaryError = data['error'];
      final message = cloudinaryError is Map
          ? '${cloudinaryError['message'] ?? 'Tải ảnh thất bại'}'
          : 'Tải ảnh minh chứng thất bại';
      throw CloudinaryUploadException(message);
    }
    final secureUrl = data['secure_url'] as String?;
    if (secureUrl == null || secureUrl.isEmpty) {
      throw const CloudinaryUploadException(
        'Cloudinary không trả về đường dẫn ảnh.',
      );
    }
    return secureUrl;
  }
}
