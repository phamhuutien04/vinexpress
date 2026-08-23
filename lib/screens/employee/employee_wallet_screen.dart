import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/wallet_service.dart';
import '../../widgets/wallet_withdrawal_sheet.dart';

class EmployeeWalletScreen extends StatefulWidget {
  const EmployeeWalletScreen({super.key});

  @override
  State<EmployeeWalletScreen> createState() => _EmployeeWalletScreenState();
}

class _EmployeeWalletScreenState extends State<EmployeeWalletScreen> {
  final _service = WalletService();
  Map<String, dynamic> _wallet = {};
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  double get _balance => (_wallet['so_du'] as num?)?.toDouble() ?? 0;

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
      final results = await Future.wait([
        _service.getWalletInfo(),
        _service.getTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as Map<String, dynamic>;
        _transactions = results[1] as List<Map<String, dynamic>>;
      });
    } on WalletServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _topUp() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yêu cầu nạp ví'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Số tiền nạp',
            suffixText: 'đ',
            helperText: 'Tối thiểu 10.000đ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
              );
              if (value != null && value >= 10000) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    try {
      final id = await _service.requestTopUp(amount);
      if (!mounted) return;
      _message('Yêu cầu nạp #$id đang chờ admin duyệt');
      await _load();
    } on WalletServiceException catch (error) {
      _message(error.message, error: true);
    }
  }

  Future<void> _withdraw() async {
    final request = await showWalletWithdrawalSheet(context, balance: _balance);
    if (request == null) return;
    try {
      final id = await _service.requestWithdrawal(amount: request.amount);
      if (!mounted) return;
      _message('Yêu cầu rút #$id đang chờ admin duyệt');
      await _load();
    } on WalletServiceException catch (error) {
      _message(error.message, error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF29BDD4)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white),
                    SizedBox(width: 9),
                    Text(
                      'VÍ NHÂN VIÊN LẤY HÀNG',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Số dư khả dụng',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  _money(_balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _topUp,
                      icon: const Icon(Icons.add_card),
                      label: const Text('Nạp tiền'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _balance >= 50000 ? _withdraw : null,
                      icon: const Icon(Icons.account_balance),
                      label: const Text('Rút tiền'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: const Color(0xFFFFF4E5),
            child: const Padding(
              padding: EdgeInsets.all(15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Đơn không COD: phí vận chuyển tiền mặt đã thu từ người gửi sẽ được đối soát và trừ khỏi ví khi xác nhận lấy hàng.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sao kê ví',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            )
          else if (_transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Chưa có giao dịch ví')),
            )
          else
            ..._transactions.map(_transactionTile),
        ],
      ),
    );
  }

  Widget _transactionTile(Map<String, dynamic> item) {
    final type = '${item['loai'] ?? ''}';
    final outgoing = type.startsWith('TRU_') || type.contains('RUT');
    final amount = (item['so_tien'] as num?)?.toDouble() ?? 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (outgoing ? Colors.red : AppColors.success)
              .withValues(alpha: .12),
          child: Icon(
            outgoing ? Icons.south_west : Icons.north_east,
            color: outgoing ? Colors.red : AppColors.success,
          ),
        ),
        title: Text(_transactionName(type)),
        subtitle: Text('${item['noi_dung'] ?? ''}'),
        trailing: Text(
          '${outgoing ? '-' : '+'}${_money(amount)}',
          style: TextStyle(
            color: outgoing ? Colors.red : AppColors.success,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _transactionName(String type) => switch (type) {
    'TRU_PHI_LAY_HANG' => 'Đối soát phí lấy hàng',
    'NAP_TIEN' => 'Nạp tiền',
    'YEU_CAU_RUT' => 'Yêu cầu rút tiền',
    'HOAN_RUT' => 'Hoàn tiền rút',
    _ => type.replaceAll('_', ' '),
  };

  String _money(num value) {
    final formatted = value.round().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    return '$formatted\u0111';
  }
}
