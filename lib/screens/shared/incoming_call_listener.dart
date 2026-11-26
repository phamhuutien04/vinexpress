import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import 'agora_voice_call_screen.dart';

class IncomingCallListener extends StatefulWidget {
  const IncomingCallListener({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  RealtimeChannel? _channel;
  String? _showingCallId;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = SupabaseConfig.client
        .channel('incoming-call-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'cuoc_goi_noi_bo',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'nguoi_nhan_auth_id',
            value: userId,
          ),
          callback: (payload) => _showIncoming(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'cuoc_goi_noi_bo',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'nguoi_nhan_auth_id',
            value: userId,
          ),
          callback: (payload) => _closeIfCallEnded(payload.newRecord),
        )
        .subscribe();
  }

  Future<void> _showIncoming(Map<String, dynamic> call) async {
    final id = '${call['id'] ?? ''}';
    if (!mounted || id.isEmpty || _showingCallId != null) return;
    final expires = DateTime.tryParse('${call['het_han_luc'] ?? ''}')?.toLocal();
    if (expires != null && DateTime.now().isAfter(expires)) return;
    final orderId = (call['don_hang_id'] as num?)?.toInt();
    if (orderId == null) return;
    _showingCallId = id;
    if (!kIsWeb) {
      await FlutterRingtonePlayer().playRingtone(looping: true, volume: 1);
    }
    if (!mounted) return;
    if (expires != null) {
      _expiryTimer?.cancel();
      _expiryTimer = Timer(expires.difference(DateTime.now()), () {
        if (_showingCallId == id && mounted) {
          Navigator.of(context, rootNavigator: true).maybePop(false);
        }
      });
    }
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const CircleAvatar(
          backgroundColor: Color(0xFF00BFA5),
          child: Icon(Icons.call, color: Colors.white),
        ),
        title: const Text('Cuộc gọi đến'),
        content: Text('${call['ten_nguoi_goi'] ?? 'VinExpress'} đang gọi cho bạn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Từ chối'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call),
            label: const Text('Nghe máy'),
          ),
        ],
      ),
    ).whenComplete(() {
      _expiryTimer?.cancel();
      if (!kIsWeb) FlutterRingtonePlayer().stop();
    });
    _showingCallId = null;
    if (answer == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgoraVoiceCallScreen(
            orderId: orderId,
            contactName: '${call['ten_nguoi_goi'] ?? 'VinExpress'}',
            notifyContact: false,
          ),
        ),
      );
    }
  }

  void _closeIfCallEnded(Map<String, dynamic> call) {
    final id = '${call['id'] ?? ''}';
    if (!mounted || id.isEmpty || id != _showingCallId) return;
    if ('${call['trang_thai']}' == 'DANG_GOI') return;
    _expiryTimer?.cancel();
    Navigator.of(context, rootNavigator: true).maybePop(false);
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    final channel = _channel;
    if (channel != null) SupabaseConfig.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
