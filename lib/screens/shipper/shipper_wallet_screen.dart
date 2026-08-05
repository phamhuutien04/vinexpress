import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/shipper_service.dart';

class ShipperWalletScreen extends StatefulWidget {
  const ShipperWalletScreen({super.key});

  @override
  State<ShipperWalletScreen> createState() => _ShipperWalletScreenState();
}

class _ShipperWalletScreenState extends State<ShipperWalletScreen> {
  final _service = ShipperService();
  List<Map<String, dynamic>> _entries = [];
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
      final entries = await _service.getDeliveredOrderHistory();
      if (mounted) setState(() => _entries = entries);
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _sum(bool paid) => _entries
      .where((entry) {
        final isPaid = entry['trang_thai_thanh_toan'] == 'DA_THANH_TOAN';
        return isPaid == paid;
      })
      .fold(
        0,
        (total, entry) =>
            total + ((entry['tien_shipper'] as num?)?.toDouble() ?? 0),
      );

  double get _total => _entries.fold(
    0,
    (total, entry) =>
        total + ((entry['tien_shipper'] as num?)?.toDouble() ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white),
                    SizedBox(width: 9),
                    Text(
                      'Ví thu nhập',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tổng thu nhập',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(_total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_entries.length} đơn giao thành công',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _BalanceCard(
                  title: 'Chờ thanh toán',
                  amount: _sum(false),
                  icon: Icons.schedule_rounded,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BalanceCard(
                  title: 'Đã thanh toán',
                  amount: _sum(true),
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Giao dịch gần đây',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_error != null)
            _EmptyWallet(message: _error!, icon: Icons.error_outline)
          else if (_entries.isEmpty)
            const _EmptyWallet(
              message: 'Chưa có thu nhập từ đơn hàng',
              icon: Icons.account_balance_wallet_outlined,
            )
          else
            ..._entries
                .take(5)
                .map(
                  (entry) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary10,
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text('${entry['ma_van_don'] ?? ''}'),
                      subtitle: Text(
                        entry['trang_thai_thanh_toan'] == 'DA_THANH_TOAN'
                            ? 'Đã thanh toán'
                            : 'Chờ thanh toán',
                      ),
                      trailing: Text(
                        '+${_money(entry['tien_shipper'])}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              _money(amount),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWallet extends StatelessWidget {
  const _EmptyWallet({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 38),
      child: Column(
        children: [
          Icon(icon, size: 46, color: AppColors.textDisabled),
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
