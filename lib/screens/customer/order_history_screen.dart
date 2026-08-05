import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/order_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final _service = OrderService();
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

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
      final orders = await _service.getCustomerOrders();
      if (mounted) setState(() => _orders = orders);
    } on OrderServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử đơn hàng')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 160),
                  const Icon(Icons.cloud_off_outlined, size: 52),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  ),
                ],
              )
            : _orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 180),
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 58,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: 12),
                  Text('Bạn chưa có đơn hàng nào', textAlign: TextAlign.center),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (_, index) =>
                    _OrderHistoryCard(order: _orders[index]),
              ),
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final status = '${order['trang_thai']}';
    final statusInfo = _status(status);
    final createdAt = DateTime.tryParse('${order['ngay_tao']}')?.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order['ma_van_don']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusInfo.label,
                    style: TextStyle(
                      color: statusInfo.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                _date(createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Divider(height: 24),
            _line(
              Icons.radio_button_checked,
              '${order['nguoi_gui_dia_chi']}',
              AppColors.primary,
            ),
            _line(
              Icons.location_on,
              '${order['nguoi_nhan_dia_chi']}',
              Colors.red,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${order['khoang_cach_km'] ?? 0} km'),
                Text(
                  _money(order['phi_van_chuyen']),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );

  static String _money(dynamic value) {
    final number = (value as num?)?.round() ?? 0;
    return '${number.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')}đ';
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static _StatusInfo _status(String status) {
    switch (status) {
      case 'CHO_LAY_HANG':
        return const _StatusInfo('Chờ lấy hàng', Colors.orange);
      case 'DA_LAY_HANG':
      case 'DANG_VAN_CHUYEN':
      case 'GIAO_CHO_SHIPPER':
      case 'DANG_GIAO_HANG':
        return const _StatusInfo('Đang giao', Colors.blue);
      case 'DA_GIAO_HANG':
        return const _StatusInfo('Đã giao', AppColors.success);
      case 'DA_HUY':
        return const _StatusInfo('Đã hủy', AppColors.error);
      default:
        return _StatusInfo(status.replaceAll('_', ' '), Colors.grey);
    }
  }
}

class _StatusInfo {
  const _StatusInfo(this.label, this.color);
  final String label;
  final Color color;
}
