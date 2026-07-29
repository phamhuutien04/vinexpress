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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: theme,
        header: (_) => pw.Row(
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
            pw.Text('HÓA ĐƠN VẬN CHUYỂN'),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Trang ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 22),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E7F8F4'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _labelValue('Mã vận đơn', '${order['ma_van_don']}', bold),
                _labelValue(
                  'Quãng đường',
                  '${order['khoang_cach_km']} km',
                  bold,
                  alignRight: true,
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
            ['Phương tiện', 'Xe tải'],
            ['Khối lượng', '${order['can_nang']} kg'],
            ['Giá trị hàng', _money(order['gia_tri_hang'])],
            ['Tiền thu hộ (COD)', _money(order['cod'])],
            ['Phí vận chuyển', _money(order['phi_van_chuyen'])],
            ['Trạng thái', 'Chờ lấy hàng'],
            ['Ghi chú', _nullableText(order['ghi_chu'])],
          ], bold),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _signature('Người gửi', 'Ký và ghi rõ họ tên', bold),
              _signature('Nhân viên tiếp nhận', 'Ký và ghi rõ họ tên', bold),
            ],
          ),
        ],
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

  static pw.Widget _signature(String title, String hint, pw.Font bold) {
    return pw.SizedBox(
      width: 180,
      child: pw.Column(
        children: [
          pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 10)),
          pw.Text(hint, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 62),
        ],
      ),
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
