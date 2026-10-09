import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_colors.dart';
import '../../services/cloudinary_service.dart';
import '../../services/customer_auth_service.dart';
import '../../services/evidence_image_service.dart';
import '../../services/transport_driver_service.dart';

class TransportIncidentReportScreen extends StatefulWidget {
  const TransportIncidentReportScreen({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<TransportIncidentReportScreen> createState() =>
      _TransportIncidentReportScreenState();
}

class _TransportIncidentReportScreenState
    extends State<TransportIncidentReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _picker = ImagePicker();
  final _cloudinary = CloudinaryService();
  final _evidenceImageService = EvidenceImageService();
  final _service = TransportDriverService();
  String _type = 'HONG_XE';
  Uint8List? _imageBytes;
  bool _submitting = false;

  static const _types = <String, String>{
    'HONG_XE': 'Hỏng xe',
    'TAI_NAN': 'Tai nạn giao thông',
    'UN_TAC': 'Ùn tắc nghiêm trọng',
    'HU_HONG_HANG': 'Hư hỏng hàng hóa',
    'MAT_NIEM_PHONG': 'Mất hoặc hỏng niêm phong',
    'THOI_TIET': 'Thời tiết nguy hiểm',
    'KHAC': 'Sự cố khác',
  };

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _imageBytes = bytes);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageBytes == null) {
      _message('Vui lòng chụp hoặc chọn ảnh minh chứng.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final tripId = (widget.trip['id'] as num).toInt();
      final tripCode = '${widget.trip['ma_chuyen']}';
      final stampedImage = await _evidenceImageService.stampTransportIncident(
        sourceBytes: _imageBytes!,
        tripId: tripId,
        tripCode: tripCode,
        incidentType: _types[_type] ?? _type,
        driverName:
            '${CustomerAuthService.currentEmployee?['ho_ten'] ?? 'Tài xế vận chuyển'}',
        vehiclePlate: '${widget.trip['bien_so_xe'] ?? 'Chưa xác định'}',
        capturedAt: DateTime.now(),
      );
      final url = await _cloudinary.uploadTransportIncident(
        imageBytes: stampedImage,
        tripId: tripId,
        tripCode: tripCode,
        incidentType: _type,
      );
      await _service.reportIncident(
        tripId: tripId,
        type: _type,
        description: _description.text,
        evidenceUrl: url,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on CloudinaryUploadException catch (error) {
      _message(error.message);
    } on TransportDriverException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Không thể gửi báo cáo: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Báo cáo sự cố')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: .35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.report_problem_rounded,
                          color: AppColors.warning,
                          size: 34,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.trip['ma_chuyen']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                'Xe ${widget.trip['bien_so_xe'] ?? 'chưa xác định'}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Loại sự cố',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: _types.entries
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.key,
                            child: Text(item.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _type = value!),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 800,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả chi tiết sự cố',
                      hintText:
                          'Ghi rõ thời điểm, vị trí, tình trạng xe hoặc hàng hóa và cách đã xử lý...',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 10
                        ? 'Mô tả phải có ít nhất 10 ký tự'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 240,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: _imageBytes == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined, size: 44),
                                SizedBox(height: 10),
                                Text('Chưa có ảnh minh chứng'),
                              ],
                            ),
                          )
                        : Image.memory(_imageBytes!, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Chụp ảnh'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Chọn ảnh'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        _submitting ? 'Đang gửi báo cáo...' : 'Gửi Admin duyệt',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
