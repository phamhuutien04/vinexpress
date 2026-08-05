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
  List<Map<String, dynamic>> _incomeEntries = [];
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic> _wallet = {};
  bool _loading = true;
  String? _error;

  double get _balance => (_wallet['so_du'] as num?)?.toDouble() ?? 0;
  double get _pendingTopUp =>
      (_wallet['tong_cho_nap'] as num?)?.toDouble() ?? 0;
  double get _pendingIncome => _sumIncome(paid: false);
  double get _paidIncome => _sumIncome(paid: true);
  double get _totalIncome => _pendingIncome + _paidIncome;

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
        _service.getDeliveredOrderHistory(),
        _service.getWalletInfo(),
        _service.getWalletTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _incomeEntries = results[0] as List<Map<String, dynamic>>;
        _wallet = results[1] as Map<String, dynamic>;
        _transactions = results[2] as List<Map<String, dynamic>>;
      });
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _sumIncome({required bool paid}) => _incomeEntries
      .where((entry) {
        return (entry['trang_thai_thanh_toan'] == 'DA_THANH_TOAN') == paid;
      })
      .fold(
        0,
        (total, entry) =>
            total + ((entry['tien_shipper'] as num?)?.toDouble() ?? 0),
      );

  Future<void> _showTopUpSheet() async {
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _TopUpSheet(),
    );
    if (amount == null) return;

    try {
      final requestId = await _service.requestWalletTopUp(amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã gửi yêu cầu #$requestId. Tiền sẽ vào ví sau khi được duyệt.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      await _load();
    } on ShipperServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 760
              ? 720.0
              : double.infinity;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 380 ? 12 : 16,
              vertical: 16,
            ),
            children: [
              Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WalletHero(
                        balance: _balance,
                        pendingTopUp: _pendingTopUp,
                        onTopUp: _showTopUpSheet,
                      ),
                      const SizedBox(height: 14),
                      _CodNotice(balance: _balance),
                      const SizedBox(height: 18),
                      Text(
                        'Thu nhập giao hàng',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _IncomeGrid(
                        total: _totalIncome,
                        orderCount: _incomeEntries.length,
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Sao kê ví',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: _load,
                            tooltip: 'Làm mới',
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_error != null)
                        _EmptyState(
                          icon: Icons.error_outline_rounded,
                          message: _error!,
                        )
                      else if (_transactions.isEmpty)
                        const _EmptyState(
                          icon: Icons.receipt_long_outlined,
                          message: 'Chưa có giao dịch ví',
                        )
                      else
                        ..._transactions.map(
                          (entry) => _TransactionTile(entry: entry),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WalletHero extends StatelessWidget {
  const _WalletHero({
    required this.balance,
    required this.pendingTopUp,
    required this.onTopUp,
  });

  final double balance;
  final double pendingTopUp;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
              SizedBox(width: 9),
              Text(
                'VÍ HOẠT ĐỘNG',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Số dư khả dụng', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onTopUp,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Nạp tiền'),
              ),
              if (pendingTopUp > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '${_money(pendingTopUp)} chờ duyệt',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodNotice extends StatelessWidget {
  const _CodNotice({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.warning),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              balance > 0
                  ? 'Bạn có thể nhận đơn COD tối đa ${_money(balance)}. '
                        'Tiền COD được khấu trừ khi nhận đơn.'
                  : 'Hãy nạp tiền để có thể nhận các đơn cần thu hộ COD.',
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeGrid extends StatelessWidget {
  const _IncomeGrid({required this.total, required this.orderCount});

  final double total;
  final int orderCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard(
              width: width,
              title: 'Số đơn đã giao',
              value: '$orderCount đơn',
              icon: Icons.inventory_2_outlined,
              color: AppColors.primary,
            ),
            _MetricCard(
              width: width,
              title: 'Số tiền đã kiếm',
              value: _money(total),
              icon: Icons.payments_outlined,
              color: AppColors.success,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final credit = _isCredit(entry['loai']);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: (credit ? AppColors.success : AppColors.error)
              .withValues(alpha: .12),
          child: Icon(
            credit ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: credit ? AppColors.success : AppColors.error,
          ),
        ),
        title: Text(
          _transactionTitle(entry['loai']),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${entry['ma_van_don'] ?? entry['noi_dung'] ?? ''}\n'
          'Số dư sau: ${_money(entry['so_du_sau'])}',
        ),
        isThreeLine: true,
        trailing: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${credit ? '+' : '-'}${_money(entry['so_tien'])}',
            style: TextStyle(
              color: credit ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet();

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  final _controller = TextEditingController();
  double? _amount;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(double value) {
    setState(() {
      _amount = value;
      _controller.text = value.round().toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nạp tiền vào ví',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Yêu cầu sẽ được cộng vào ví sau khi quản trị viên xác nhận.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [50000, 100000, 200000, 500000]
                  .map(
                    (value) => ChoiceChip(
                      selected: _amount == value,
                      label: Text(_money(value)),
                      onSelected: (_) => _select(value.toDouble()),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền muốn nạp',
                suffixText: 'đ',
                helperText: 'Tối thiểu 10.000đ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onChanged: (text) {
                setState(() {
                  _amount = double.tryParse(
                    text.replaceAll(RegExp(r'[^0-9]'), ''),
                  );
                });
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: (_amount ?? 0) < 10000
                  ? null
                  : () => Navigator.pop(context, _amount),
              icon: const Icon(Icons.send_rounded),
              label: Text(
                (_amount ?? 0) >= 10000
                    ? 'Gửi yêu cầu ${_money(_amount)}'
                    : 'Gửi yêu cầu nạp tiền',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
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

bool _isCredit(dynamic type) =>
    type == 'NAP_TIEN' || type == 'HOAN_COD' || type == 'THU_NHAP_GIAO_HANG';

String _transactionTitle(dynamic type) => switch (type) {
  'NAP_TIEN' => 'Nạp tiền',
  'TAM_GIU_COD' => 'Khấu trừ đơn COD',
  'HOAN_COD' => 'Hoàn tiền COD',
  'THU_NHAP_GIAO_HANG' => 'Thu nhập giao hàng',
  _ => 'Điều chỉnh số dư',
};
