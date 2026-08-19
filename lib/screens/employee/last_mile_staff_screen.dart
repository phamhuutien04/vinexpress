import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/last_mile_staff_service.dart';
import '../auth/login_screen.dart';

class LastMileStaffScreen extends StatefulWidget {
  const LastMileStaffScreen({super.key});
  @override
  State<LastMileStaffScreen> createState() => _LastMileStaffScreenState();
}

class _LastMileStaffScreenState extends State<LastMileStaffScreen> {
  final _service = LastMileStaffService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  bool get _pickup =>
      CustomerAuthService.currentEmployee?['vai_tro'] == 'NHAN_VIEN_LAY_HANG';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _service.tasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _pickup ? 'Đơn lấy hàng trong khu vực' : 'Kiện hàng đã quét nhận',
      ),
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!, textAlign: TextAlign.center))
        : _tasks.isEmpty
        ? Center(
            child: Text(
              _pickup
                  ? 'Chưa có đơn lấy hàng trong phường/xã của bạn'
                  : 'Hãy quét mã QR trên kiện hàng tại kho',
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _tasks.length,
              itemBuilder: (_, i) => _taskCard(_tasks[i]),
            ),
          ),
    floatingActionButton: _pickup
        ? null
        : FloatingActionButton.extended(
            onPressed: _scanParcel,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Quét kiện tại kho'),
          ),
  );

  Widget _taskCard(Map<String, dynamic> item) {
    final delivering = item['trang_thai'] == 'DANG_GIAO_HANG';
    final claimed = item['da_nhan'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['ma_van_don']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    _pickup
                        ? claimed
                              ? 'Bạn đã nhận'
                              : 'Đang mở'
                        : 'Đã quét',
                  ),
                ),
              ],
            ),
            Text(
              '${item['ten_khach']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('${item['so_dien_thoai']}'),
            const SizedBox(height: 6),
            Text('${item['dia_chi']}'),
            const Divider(height: 24),
            Text(
              _pickup
                  ? 'Mang về: ${item['ten_kho']}'
                  : 'Lấy tại: ${item['ten_kho']}',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _pickup && !claimed
                  ? _claimPickup((item['id'] as num).toInt())
                  : _confirm((item['id'] as num).toInt()),
              icon: Icon(
                _pickup && !claimed
                    ? Icons.pan_tool_alt_outlined
                    : delivering
                    ? Icons.check_circle_outline
                    : Icons.delivery_dining,
              ),
              label: Text(
                _pickup
                    ? claimed
                          ? 'Đã lấy và đưa về kho'
                          : 'Nhận đơn này'
                    : delivering
                    ? 'Xác nhận đã giao'
                    : 'Bắt đầu giao hàng',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimPickup(int id) => _run(() => _service.claimPickup(id));
  Future<void> _confirm(int id) => _run(() => _service.confirm(id));

  Future<void> _run(Future<dynamic> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _scanParcel() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ParcelScannerPage()),
    );
    if (code == null || code.trim().isEmpty) return;
    await _run(() => _service.scanDeliveryParcel(code));
  }

  Future<void> _logout() async {
    await CustomerAuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

class _ParcelScannerPage extends StatefulWidget {
  const _ParcelScannerPage();
  @override
  State<_ParcelScannerPage> createState() => _ParcelScannerPageState();
}

class _ParcelScannerPageState extends State<_ParcelScannerPage> {
  bool _handled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét mã kiện hàng')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (_handled || capture.barcodes.isEmpty) return;
            final value = capture.barcodes.first.rawValue;
            if (value == null || value.trim().isEmpty) return;
            _handled = true;
            Navigator.of(context).pop(value.trim());
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 4),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            'Đưa mã QR trên kiện hàng vào giữa khung',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
