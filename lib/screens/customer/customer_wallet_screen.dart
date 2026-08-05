import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/wallet_service.dart';
import '../../widgets/wallet_withdrawal_sheet.dart';

class CustomerWalletScreen extends StatefulWidget {
  const CustomerWalletScreen({super.key});

  @override
  State<CustomerWalletScreen> createState() => _CustomerWalletScreenState();
}

class _CustomerWalletScreenState extends State<CustomerWalletScreen> {
  final _service = WalletService();
  Map<String, dynamic> _wallet = {};
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  double get _balance => (_wallet['so_du'] as num?)?.toDouble() ?? 0;
  double get _pendingWithdrawal =>
      (_wallet['tong_cho_rut'] as num?)?.toDouble() ?? 0;

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

  Future<void> _withdraw() async {
    final request = await showWalletWithdrawalSheet(context, balance: _balance);
    if (request == null) return;
    try {
      final id = await _service.requestWithdrawal(amount: request.amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yêu cầu rút #$id đang chờ admin duyệt.')),
      );
      await _load();
    } on WalletServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ví của tôi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
                            Icon(
                              Icons.account_balance_wallet,
                              color: Colors.white,
                            ),
                            SizedBox(width: 9),
                            Text(
                              'VÍ VINEXPRESS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Số dư khả dụng',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _money(_balance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tiền COD được cộng sau khi đơn giao thành công',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _balance >= 50000 ? _withdraw : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                          ),
                          icon: const Icon(Icons.account_balance_rounded),
                          label: const Text('Rút tiền'),
                        ),
                        if (_pendingWithdrawal > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${_money(_pendingWithdrawal)} đang chờ admin duyệt rút',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Lịch sử giao dịch',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_error != null)
                    _Empty(message: _error!)
                  else if (_transactions.isEmpty)
                    const _Empty(message: 'Chưa có giao dịch ví')
                  else
                    ..._transactions.map((item) => _Transaction(item: item)),
                ],
              ),
            ),
    );
  }
}

class _Transaction extends StatelessWidget {
  const _Transaction({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final credit = const {
      'NAP_TIEN',
      'NHAN_COD',
      'HOAN_COD',
      'HOAN_RUT',
      'THU_NHAP_GIAO_HANG',
    }.contains(item['loai']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (credit ? AppColors.success : AppColors.error)
              .withValues(alpha: .12),
          child: Icon(
            credit ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: credit ? AppColors.success : AppColors.error,
          ),
        ),
        title: Text(_title(item['loai'])),
        subtitle: Text('${item['ma_van_don'] ?? item['noi_dung'] ?? ''}'),
        trailing: Text(
          '${credit ? '+' : '-'}${_money(item['so_tien'])}',
          style: TextStyle(
            color: credit ? AppColors.success : AppColors.error,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: AppColors.textDisabled,
          ),
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

String _title(dynamic type) => switch (type) {
  'NHAN_COD' => 'Nhận tiền COD',
  'NAP_TIEN' => 'Nạp tiền',
  'RUT_TIEN' => 'Rút tiền',
  'YEU_CAU_RUT' => 'Yêu cầu rút tiền',
  'HOAN_RUT' => 'Hoàn tiền rút bị từ chối',
  'TRU_COD' => 'Khấu trừ COD',
  'HOAN_COD' => 'Hoàn tiền COD',
  'THU_NHAP_GIAO_HANG' => 'Thu nhập giao hàng',
  _ => 'Điều chỉnh số dư',
};
