import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class EvidenceImageService {
  // Flutter Web mã hóa PNG trên luồng giao diện. Giới hạn này vẫn đủ rõ để
  // đọc thông tin minh chứng nhưng tránh treo trình duyệt với ảnh camera lớn.
  static const int _maximumImageDimension = 800;

  Future<Uint8List> stamp({
    required Uint8List sourceBytes,
    required int orderId,
    required String trackingCode,
    required String evidenceLabel,
    required String employeeName,
    required String address,
    required double latitude,
    required double longitude,
    required DateTime capturedAt,
  }) async {
    final source = await _decode(sourceBytes);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final width = source.width.toDouble();
    final height = source.height.toDouble();
    canvas.drawImage(source, Offset.zero, Paint());

    final text = [
      'VINEXPRESS - $evidenceLabel',
      'Đơn #$orderId • $trackingCode',
      'Nhân viên: $employeeName',
      'Địa chỉ: $address',
      'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
      'Thời gian: ${_formatDateTime(capturedAt)}',
    ].join('\n');

    // Co chữ theo cả chiều rộng và chiều cao để ảnh dọc, ngang hoặc ảnh nhỏ
    // đều hiển thị đủ phần thông tin mà không tràn khỏi khung.
    var fontSize = (width * .032).clamp(12.0, 42.0);
    final maxPanelHeight = height * .48;
    late TextPainter painter;
    late double padding;
    while (true) {
      padding = (fontSize * .7).clamp(7.0, 30.0);
      painter = _textPainter(text, fontSize)
        ..layout(maxWidth: (width - padding * 2).clamp(1.0, width));
      if (painter.height + padding * 2 <= maxPanelHeight || fontSize <= 9) {
        break;
      }
      fontSize -= 1;
    }
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

  TextPainter _textPainter(String text, double fontSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          height: 1.25,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 9,
      ellipsis: '…',
    );
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final sourceWidth = descriptor.width;
    final sourceHeight = descriptor.height;
    final largestSide = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
    final scale = largestSide > _maximumImageDimension
        ? _maximumImageDimension / largestSide
        : 1.0;
    final targetWidth = (sourceWidth * scale).round();
    final targetHeight = (sourceHeight * scale).round();
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
