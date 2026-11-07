import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../services/payos_service.dart';
import '../../services/shipper_service.dart';
import '../../widgets/wallet_withdrawal_sheet.dart';
import '../../widgets/shipper_income_chart.dart';

class ShipperWalletScreen extends StatefulWidget {
  const ShipperWalletScreen({super.key});

  @override
  State<ShipperWalletScreen> createState() => _ShipperWalletScreenState();
}

class _ShipperWalletScreenState extends State<ShipperWalletScreen> {
  final _service = ShipperService();
  final _payosService = PayosService();
  List<Map<String, dynamic>> _incomeEntries = [];
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic> _wallet = {};
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  RealtimeChannel? _walletChannel;
  Timer? _realtimeDebounce;
  Timer? _walletPollingTimer;

  double get _balance => (_wallet['so_du'] as num?)?.toDouble() ?? 0;
  double get _pendingWithdrawal =>
      (_wallet['tong_cho_rut'] as num?)?.toDouble() ?? 0;
  double get _pendingIncome => _sumIncome(paid: false);
  double get _paidIncome => _sumIncome(paid: true);
  double get _totalIncome => _pendingIncome + _paidIncome;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeWalletRealtime();
    _walletPollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshSilently(),
    );
  }

  void _subscribeWalletRealtime() {
    _walletChannel = Supabase.instance.client
        .channel(
          'shipper-wallet-${Supabase.instance.client.auth.currentUser?.id}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vi',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'giao_dich_vi',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .subscribe();
  }

  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _walletPollingTimer?.cancel();
    _realtimeDebounce = Timer(
      const Duration(milliseconds: 250),
      _refreshSilently,
    );
  }

  Future<void> _refreshSilently() async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
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
        _error = null;
      });
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    final channel = _walletChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
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
      final checkout = await _payosService.createWalletTopUp(
        amount: amount.round(),
      );
      if (!mounted) return;
      await _showPayosQr(checkout);
      if (!mounted) return;
    } on PayosServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<bool> _showPayosQr(PayosCheckout checkout) async {
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayosQrDialog(checkout: checkout),
    );
    if (paid == true) unawaited(_refreshSilently());
    return paid == true;
  }

  Future<void> _showWithdrawalSheet() async {
    final request = await showWalletWithdrawalSheet(context, balance: _balance);
    if (request == null) return;
    try {
      final id = await _service.requestWalletWithdrawal(amount: request.amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yêu cầu rút #$id đang chờ admin duyệt.')),
      );
      await _load();
    } on ShipperServiceException catch (error) {
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
                        pendingWithdrawal: _pendingWithdrawal,
                        onTopUp: _showTopUpSheet,
                        onWithdraw: _showWithdrawalSheet,
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
                      const SizedBox(height: 14),
                      ShipperIncomeChart(
                        entries: _incomeEntries,
                        errorMessage: _error,
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
    required this.pendingWithdrawal,
    required this.onTopUp,
    required this.onWithdraw,
  });

  final double balance;
  final double pendingWithdrawal;
  final VoidCallback onTopUp;
  final VoidCallback onWithdraw;

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
              OutlinedButton.icon(
                onPressed: balance >= 50000 ? onWithdraw : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text('Rút tiền'),
              ),
              if (pendingWithdrawal > 0)
                Text(
                  '${_money(pendingWithdrawal)} đang chờ rút',
                  style: const TextStyle(color: Colors.white),
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

class _PayosQrDialog extends StatefulWidget {
  const _PayosQrDialog({required this.checkout});

  final PayosCheckout checkout;

  @override
  State<_PayosQrDialog> createState() => _PayosQrDialogState();
}

class _PayosQrDialogState extends State<_PayosQrDialog> {
  final _payosService = PayosService();
  Timer? _timer;
  bool _checking = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _checkPaid());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkPaid() async {
    if (_checking) return;
    _checking = true;
    try {
      final paid = await _payosService.isPaymentCompleted(
        widget.checkout.orderCode,
      );
      if (paid && mounted) Navigator.pop(context, true);
    } catch (_) {
      // Tiếp tục chờ: webhook có thể đến chậm vài giây sau khi ngân hàng báo xong.
    } finally {
      _checking = false;
    }
  }

  Future<void> _cancelPayment() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await _payosService.cancelWalletTopUp(widget.checkout.orderCode);
      if (mounted) Navigator.pop(context, false);
    } on PayosServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrCode = widget.checkout.qrCode;
    final compact = MediaQuery.sizeOf(context).width < 420;
    final qrSize = compact ? 190.0 : 240.0;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Quét QR để nạp ví',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Thanh toán ${_money(widget.checkout.amount)} qua ứng dụng ngân hàng.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (qrCode != null && qrCode.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    data: qrCode,
                    version: QrVersions.auto,
                    size: qrSize,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Icon(Icons.qr_code_2_rounded, size: 96),
                ),
              const SizedBox(height: 14),
              const Text(
                'QR sẽ tự đóng khi thanh toán thành công và ví được cộng tiền. Chọn “Hủy” sẽ hủy QR này.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelling ? null : _cancelPayment,
                      child: _cancelling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _cancelling
                          ? null
                          : () async {
                              final opened = await launchUrl(
                                Uri.parse(widget.checkout.checkoutUrl),
                                mode: LaunchMode.externalApplication,
                              );
                              if (!context.mounted || opened) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Không mở được trang thanh toán.')),
                              );
                            },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Mở thanh toán'),
                    ),
                  ),
                ],
              ),
            ],
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
              'Quét VietQR bằng ứng dụng ngân hàng. Ví tự cộng tiền sau khi thanh toán thành công.',
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
                    ? 'Thanh toán ${_money(_amount)}'
                    : 'Thanh toán',
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
    type == 'NAP_TIEN' ||
    type == 'HOAN_COD' ||
    type == 'HOAN_RUT' ||
    type == 'THU_NHAP_GIAO_HANG';

String _transactionTitle(dynamic type) => switch (type) {
  'NAP_TIEN' => 'Nạp tiền',
  'TAM_GIU_COD' => 'Khấu trừ đơn COD',
  'HOAN_COD' => 'Hoàn tiền COD',
  'YEU_CAU_RUT' => 'Yêu cầu rút tiền',
  'RUT_TIEN' => 'Rút tiền',
  'HOAN_RUT' => 'Hoàn tiền rút bị từ chối',
  'THU_NHAP_GIAO_HANG' => 'Thu nhập giao hàng',
  _ => 'Điều chỉnh số dư',
};
