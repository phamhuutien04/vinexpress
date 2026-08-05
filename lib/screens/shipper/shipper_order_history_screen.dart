import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/shipper_service.dart';

class ShipperOrderHistoryScreen extends StatefulWidget {
  const ShipperOrderHistoryScreen({super.key});

  @override
  State<ShipperOrderHistoryScreen> createState() =>
      _ShipperOrderHistoryScreenState();
}

class _ShipperOrderHistoryScreenState extends State<ShipperOrderHistoryScreen> {
  final _service = ShipperService();
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
      final orders = await _service.getDeliveredOrderHistory();
      if (mounted) setState(() => _orders = orders);
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalIncome => _orders.fold(
    0,
    (total, order) =>
        total + ((order['tien_shipper'] as num?)?.toDouble() ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IncomeSummary(total: _totalIncome, orderCount: _orders.length),
          const SizedBox(height: 20),
          Text('Đơn đã giao', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_error != null)
            _MessageState(icon: Icons.error_outline_rounded, message: _error!)
          else if (_orders.isEmpty)
            const _MessageState(
              icon: Icons.history_rounded,
              message: 'Bạn chưa có đơn hàng đã giao',
            )
          else
            ..._orders.map((order) => _DeliveredOrderCard(order: order)),
        ],
      ),
    );
  }
}

class _IncomeSummary extends StatelessWidget {
  const _IncomeSummary({required this.total, required this.orderCount});

  final double total;
  final int orderCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tổng thu nhập đã ghi nhận',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            _money(total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$orderCount đơn giao thành công',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DeliveredOrderCard extends StatelessWidget {
  const _DeliveredOrderCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
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
                    '${order['ma_van_don'] ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _money(order['tien_shipper']),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line(Icons.my_location_rounded, '${order['nguoi_gui_dia_chi']}'),
            _line(Icons.flag_rounded, '${order['nguoi_nhan_dia_chi']}'),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sàn ${_percent(order['phan_tram_san'])}: '
                    '${_money(order['tien_san'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  order['trang_thai_thanh_toan'] == 'DA_THANH_TOAN'
                      ? 'Đã thanh toán'
                      : 'Chưa thanh toán',
                  style: TextStyle(
                    color: order['trang_thai_thanh_toan'] == 'DA_THANH_TOAN'
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textDisabled),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _money(dynamic value) {
  final number = (value as num?)?.round() ?? 0;
  final formatted = number.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return '$formattedđ';
}

String _percent(dynamic value) {
  final number = (value as num?)?.toDouble() ?? 0;
  return number == number.roundToDouble()
      ? '${number.round()}%'
      : '${number.toStringAsFixed(1)}%';
}
