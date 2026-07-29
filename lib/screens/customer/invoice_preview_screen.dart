import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../services/invoice_service.dart';

class InvoicePreviewScreen extends StatelessWidget {
  const InvoicePreviewScreen({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hóa đơn vận chuyển')),
      body: PdfPreview(
        build: (_) => InvoiceService.buildPdf(order),
        pdfFileName: 'hoa_don_${order['ma_van_don']}.pdf',
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}
