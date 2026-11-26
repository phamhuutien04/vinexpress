import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class AgoraCallException implements Exception {
  const AgoraCallException(this.message);

  final String message;
}

class AgoraCallCredentials {
  const AgoraCallCredentials({
    required this.appId,
    required this.token,
    required this.channel,
    required this.uid,
    required this.orderCode,
    this.callId,
  });

  final String appId;
  final String token;
  final String channel;
  final int uid;
  final String orderCode;
  final String? callId;
}

class AgoraCallService {
  AgoraCallService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  Future<AgoraCallCredentials> createCredentials(
    int orderId, {
    bool notify = true,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'agora-call-token',
        body: {'orderId': orderId, 'notify': notify},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw AgoraCallException('${data['error']}');
      return AgoraCallCredentials(
        appId: '${data['appId']}',
        token: '${data['token']}',
        channel: '${data['channel']}',
        uid: (data['uid'] as num).toInt(),
        orderCode: '${data['orderCode'] ?? ''}',
        callId: data['callId'] as String?,
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw AgoraCallException('${details['error']}');
      }
      if (details is String) {
        try {
          final parsed = jsonDecode(details);
          if (parsed is Map && parsed['error'] != null) {
            throw AgoraCallException('${parsed['error']}');
          }
        } catch (error) {
          if (error is AgoraCallException) rethrow;
        }
      }
      throw AgoraCallException(
        'Dịch vụ gọi phản hồi lỗi: ${error.reasonPhrase ?? error.status}',
      );
    } on AgoraCallException {
      rethrow;
    } catch (error) {
      throw AgoraCallException('Không thể khởi tạo cuộc gọi: $error');
    }
  }

  Future<void> endInvite(String? callId) async {
    if (callId == null || callId.isEmpty) return;
    try {
      await _client.functions.invoke(
        'agora-call-token',
        body: {'action': 'end', 'callId': callId},
      );
    } catch (_) {
      // Cuộc gọi đã được đóng cục bộ; trạng thái server chỉ phục vụ đồng bộ UI.
    }
  }
}
