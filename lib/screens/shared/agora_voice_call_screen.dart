import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_colors.dart';
import '../../services/agora_call_service.dart';

class AgoraVoiceCallScreen extends StatefulWidget {
  const AgoraVoiceCallScreen({
    super.key,
    required this.orderId,
    required this.contactName,
    this.notifyContact = true,
  });

  final int orderId;
  final String contactName;
  final bool notifyContact;

  @override
  State<AgoraVoiceCallScreen> createState() => _AgoraVoiceCallScreenState();
}

class _AgoraVoiceCallScreenState extends State<AgoraVoiceCallScreen> {
  final _service = AgoraCallService();
  RtcEngine? _engine;
  String? _error;
  String _status = 'Đang kết nối…';
  bool _muted = false;
  bool _speaker = true;
  bool _connected = false;
  String _stage = 'chuẩn bị gọi';
  Timer? _unansweredCallTimer;
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  String? _callId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _stage = 'xin quyền micro';
    if (!await Permission.microphone.request().isGranted) {
      if (mounted) setState(() => _error = 'Cần cho phép micro để gọi thoại.');
      return;
    }
    try {
      _stage = 'tạo token';
      final credentials = await _service.createCredentials(
        widget.orderId,
        notify: widget.notifyContact,
      );
      _callId = credentials.callId;
      _stage = 'tạo Agora RTC';
      final engine = createAgoraRtcEngine();
      _engine = engine;
      _stage = 'khởi tạo Agora RTC';
      await engine.initialize(
        RtcEngineContext(
          appId: credentials.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) {
              setState(
                () => _status = 'Đang chờ ${widget.contactName} vào cuộc gọi',
              );
            }
            if (widget.notifyContact) {
              _unansweredCallTimer?.cancel();
              _unansweredCallTimer = Timer(const Duration(seconds: 30), () {
                if (!_connected && mounted) _endUnansweredCall();
              });
            }
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            _unansweredCallTimer?.cancel();
            _durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted) setState(() => _callDuration += const Duration(seconds: 1));
            });
            if (mounted) {
              setState(() {
                _connected = true;
                _status = 'Đang gọi';
              });
            }
          },
          onUserOffline: (connection, remoteUid, reason) {
            _durationTimer?.cancel();
            if (mounted) unawaited(_endAfterRemoteLeft());
          },
          onError: (err, msg) {
            if (mounted) setState(() => _error = 'Không thể gọi: $msg');
          },
        ),
      );
      _stage = 'vào phòng gọi';
      await engine.joinChannel(
        token: credentials.token,
        channelId: credentials.channel,
        uid: credentials.uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } on AgoraCallException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Không thể kết nối ở bước $_stage: $error');
      }
    }
  }

  Future<void> _toggleMute() async {
    final value = !_muted;
    await _engine?.muteLocalAudioStream(value);
    if (mounted) setState(() => _muted = value);
  }

  Future<void> _toggleSpeaker() async {
    final value = !_speaker;
    if (!kIsWeb) await _engine?.setEnableSpeakerphone(value);
    if (mounted) setState(() => _speaker = value);
  }

  Future<void> _endCall() async {
    _unansweredCallTimer?.cancel();
    _durationTimer?.cancel();
    await _service.endInvite(_callId);
    await _engine?.leaveChannel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endUnansweredCall() async {
    await _service.endInvite(_callId);
    await _engine?.leaveChannel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không có phản hồi sau 30 giây. Đã kết thúc cuộc gọi.')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _endAfterRemoteLeft() async {
    await _service.endInvite(_callId);
    await _engine?.leaveChannel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.contactName} đã kết thúc cuộc gọi.')),
    );
    Navigator.of(context).pop();
  }

  String get _durationText {
    final minutes = _callDuration.inMinutes.toString().padLeft(2, '0');
    final seconds = (_callDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _unansweredCallTimer?.cancel();
    _durationTimer?.cancel();
    final engine = _engine;
    if (engine != null) {
      engine.leaveChannel();
      engine.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      backgroundColor: const Color(0xFF062F2C),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: _endCall,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                const Spacer(),
                CircleAvatar(
                  radius: 58,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    widget.contactName.trim().isEmpty
                        ? '?'
                        : widget.contactName.trim()[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 22),
                Text(widget.contactName, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(error ?? (_connected ? 'Đang gọi • $_durationText' : _status), textAlign: TextAlign.center, style: TextStyle(color: error == null ? Colors.white70 : const Color(0xFFFFB4AB), fontSize: 16)),
                if (_connected) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Kết nối bảo mật qua VinExpress', style: TextStyle(color: Colors.white54))),
                const Spacer(),
                if (error != null)
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _status = 'Đang kết nối…';
                      });
                      _start();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundButton(icon: _muted ? Icons.mic_off : Icons.mic, label: _muted ? 'Bật micro' : 'Tắt micro', onPressed: _toggleMute),
                    if (!kIsWeb)
                      _roundButton(icon: _speaker ? Icons.volume_up : Icons.volume_off, label: 'Loa ngoài', onPressed: _toggleSpeaker),
                    _roundButton(icon: Icons.call_end, label: 'Kết thúc', color: AppColors.error, onPressed: _endCall),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({required IconData icon, required String label, required VoidCallback onPressed, Color? color}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(19), backgroundColor: color ?? Colors.white24),
        child: Icon(icon, color: Colors.white),
      ),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ],
  );
}
