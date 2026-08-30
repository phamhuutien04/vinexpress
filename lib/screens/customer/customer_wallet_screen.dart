import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/wallet_service.dart';
import '../../widgets/wallet_withdrawal_sheet.dart';
import 'widgets/customer_design.dart';

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
        SnackBar(content: Text('Yêu cầu rút #$id đang chờ duyệt.')),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ví của tôi'),
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: CustomerUi.pagePadding(constraints.maxWidth),
          children: [
            CustomerConstrained(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading)
                    const CustomerSkeleton(height: 235, radius: 24)
                  else
                    _BalancePanel(
                      balance: _balance,
                      pendingWithdrawal: _pendingWithdrawal,
                      onWithdraw: _balance >= 50000 ? _withdraw : null,
                    ),
                  const SizedBox(height: 28),
                  CustomerSectionHeader(
                    title: 'Giao dịch gần đây',
                    subtitle: _transactions.isEmpty
                        ? null
                        : '${_transactions.length} giao dịch',
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Column(
                      children: [
                        CustomerSkeleton(height: 76),
                        SizedBox(height: 8),
                        CustomerSkeleton(height: 76),
                        SizedBox(height: 8),
                        CustomerSkeleton(height: 76),
                      ],
                    )
                  else if (_error != null)
                    CustomerPanel(
                      child: CustomerEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Chưa tải được ví',
                        message: _error!,
                        actionLabel: 'Thử lại',
                        onAction: _load,
                      ),
                    )
                  else if (_transactions.isEmpty)
                    const CustomerPanel(
                      child: CustomerEmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Chưa có giao dịch',
                        message:
                            'Các khoản tiền vào và ra sẽ xuất hiện tại đây.',
                      ),
                    )
                  else
                    _TransactionList(items: _transactions),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({
    required this.balance,
    required this.pendingWithdrawal,
    required this.onWithdraw,
  });

  final double balance;
  final double pendingWithdrawal;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF143B38),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF143B38).withValues(alpha: 0.18),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 580;
        final balanceInfo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                ),
                SizedBox(width: 9),
                Text(
                  'Ví VinExpress',
                  style: TextStyle(
                    color: Color(0xFFD3E5E2),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Số dư khả dụng',
              style: TextStyle(color: Color(0xFF9EDBD3)),
            ),
            const SizedBox(height: 5),
            Text(
              _money(balance),
              style: const TextStyle(
                color: Color(0xFFF4FAF9),
                fontSize: 34,
                height: 1.1,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (pendingWithdrawal > 0) ...[
              const SizedBox(height: 10),
              Text(
                '${_money(pendingWithdrawal)} đang chờ duyệt rút',
                style: const TextStyle(color: Color(0xFFD3E5E2)),
              ),
            ],
          ],
        );
        final action = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onWithdraw,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white24,
                  disabledForegroundColor: Colors.white60,
                ),
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text('Rút tiền'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Số tiền rút tối thiểu là 50.000đ',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9EDBD3), fontSize: 12),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [balanceInfo, const SizedBox(height: 22), action],
          );
        }
        return Row(
          children: [
            Expanded(child: balanceInfo),
            const SizedBox(width: 30),
            SizedBox(width: 210, child: action),
          ],
        );
      },
    ),
  );
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => CustomerPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _Transaction(item: items[index]),
          if (index < items.length - 1)
            Divider(
              height: 1,
              indent: 72,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
        ],
      ],
    ),
  );
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
    final color = credit ? const Color(0xFF287A4B) : AppColors.error;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          credit ? Icons.south_west_rounded : Icons.north_east_rounded,
          color: color,
        ),
      ),
      title: Text(
        _title(item['loai']),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${item['ma_van_don'] ?? item['noi_dung'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${credit ? '+' : '-'}${_money(item['so_tien'])}',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
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
