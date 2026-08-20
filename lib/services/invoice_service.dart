import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceService {
  InvoiceService._();

  static Future<Uint8List> buildPdf(Map<String, dynamic> order) async {
    final document = pw.Document();
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final trackingCode = '${order['ma_van_don']}'.trim();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: theme,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'VINEXPRESS',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#00BFA5'),
                  ),
                ),
                pw.Text('PHIẾU GỬI HÀNG', style: pw.TextStyle(font: bold)),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E7F8F4'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  _labelValue('Mã vận đơn', '${order['ma_van_don']}', bold),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: trackingCode,
                    width: 86,
                    height: 86,
                    drawText: false,
                  ),
                  pw.SizedBox(width: 18),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: trackingCode,
                          height: 48,
                          drawText: false,
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          trackingCode,
                          style: pw.TextStyle(font: bold, fontSize: 11),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            _section('THÔNG TIN NGƯỜI GỬI', [
              ['Họ tên', '${order['nguoi_gui_ten']}'],
              ['Số điện thoại', '${order['nguoi_gui_sdt']}'],
              ['Địa chỉ', '${order['nguoi_gui_dia_chi']}'],
            ], bold),
            pw.SizedBox(height: 16),
            _section('THÔNG TIN NGƯỜI NHẬN', [
              ['Họ tên', '${order['nguoi_nhan_ten']}'],
              ['Số điện thoại', '${order['nguoi_nhan_sdt']}'],
              ['Địa chỉ', '${order['nguoi_nhan_dia_chi']}'],
            ], bold),
            pw.SizedBox(height: 16),
            _section('CHI TIẾT VẬN CHUYỂN', [
              ['Khối lượng', '${order['can_nang']} kg'],
              ['Giá trị hàng', _money(order['gia_tri_hang'])],
              ['Tiền thu hộ (COD)', _money(order['cod'])],
              ['Phí vận chuyển', _money(order['phi_van_chuyen'])],
              ['Trạng thái', 'Chờ lấy hàng'],
              ['Ghi chú', _nullableText(order['ghi_chu'])],
            ], bold),
          ],
        ),
      ),
    );
    return document.save();
  }

  static pw.Widget _section(
    String title,
    List<List<String>> rows,
    pw.Font bold,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: bold,
            fontSize: 11,
            color: PdfColor.fromHex('#00796B'),
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: .6),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.1),
            1: pw.FlexColumnWidth(2.9),
          },
          children: rows
              .map(
                (row) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        row[0],
                        style: pw.TextStyle(font: bold, fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        row[1],
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  static pw.Widget _labelValue(
    String label,
    String value,
    pw.Font bold, {
    bool alignRight = false,
  }) {
    return pw.Column(
      crossAxisAlignment: alignRight
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 3),
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 12)),
      ],
    );
  }

  static String _money(dynamic value) {
    final number = (value as num?)?.round() ?? 0;
    final text = number.toString();
    return '${text.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';
  }

  static String _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Không có' : text;
  }
}
