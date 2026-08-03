import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/config/cloudinary_config.dart';

class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(this.message);
  final String message;
}

class CloudinaryService {
  Future<String> uploadEvidence({
    required XFile image,
    required String trackingCode,
    required String evidenceType,
  }) async {
    final bytes = await image.readAsBytes();
    final request =
        http.MultipartRequest('POST', CloudinaryConfig.imageUploadUri)
          ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
          ..fields['context'] = 'tracking_code=$trackingCode|type=$evidenceType'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: image.name.isEmpty ? 'evidence.jpg' : image.name,
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
