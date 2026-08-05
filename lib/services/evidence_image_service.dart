import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class EvidenceImageService {
  Future<Uint8List> stamp({
    required Uint8List sourceBytes,
    required int orderId,
    required String trackingCode,
    required String evidenceLabel,
    required String address,
    required double latitude,
    required double longitude,
    required DateTime capturedAt,
    required String locationSource,
  }) async {
    final source = await _decode(sourceBytes);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final width = source.width.toDouble();
    final height = source.height.toDouble();
    canvas.drawImage(source, Offset.zero, Paint());

    final fontSize = (width * .032).clamp(18.0, 42.0);
    final padding = fontSize * .7;
    final text = [
      'VINEXPRESS - $evidenceLabel',
      'Đơn #$orderId • $trackingCode',
      'Địa chỉ: $address',
      'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
      'Nguồn vị trí: $locationSource',
      'Thời gian: ${_formatDateTime(capturedAt)}',
    ].join('\n');
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          height: 1.3,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 7,
      ellipsis: '…',
    )..layout(maxWidth: width - padding * 2);
    final panelHeight = painter.height + padding * 2;
    final panelTop = (height - panelHeight).clamp(0.0, height);
    canvas.drawRect(
      Rect.fromLTWH(0, panelTop, width, panelHeight),
      Paint()..color = Colors.black.withValues(alpha: .68),
    );
    painter.paint(canvas, Offset(padding, panelTop + padding));

    final result = await recorder.endRecording().toImage(
      source.width,
      source.height,
    );
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Không thể tạo ảnh minh chứng.');
    return byteData.buffer.asUint8List();
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
