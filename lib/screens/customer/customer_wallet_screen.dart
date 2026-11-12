import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../services/payos_service.dart';
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
  final _payosService = PayosService();
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

  Future<void> _topUpWithPayos() async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return const _CustomerTopUpAmountSheet();
      },
    );
    if (amount == null || !mounted) return;

    try {
      final checkout = await _payosService.createWalletTopUp(amount: amount);
      if (!mounted) return;
      final paid = await _showPayosQr(checkout);
      if (paid && mounted) await _load();
    } on PayosServiceException catch (error) {
      if (mounted) _message(error.message, error: true);
    }
  }

  Future<bool> _showPayosQr(PayosCheckout checkout) async {
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomerPayosQrDialog(checkout: checkout),
    );
    return paid == true;
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
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
                      onTopUp: _loading ? null : _topUpWithPayos,
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

class _CustomerTopUpAmountSheet extends StatefulWidget {
  const _CustomerTopUpAmountSheet();

  @override
  State<_CustomerTopUpAmountSheet> createState() =>
      _CustomerTopUpAmountSheetState();
}

class _CustomerTopUpAmountSheetState extends State<_CustomerTopUpAmountSheet> {
  final _controller = TextEditingController();
  int _amount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setAmount(int amount) {
    _controller.value = TextEditingValue(
      text: '$amount',
      selection: TextSelection.collapsed(offset: '$amount'.length),
    );
    setState(() => _amount = amount);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final valid = _amount >= 10000 && _amount <= 50000000;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nạp tiền vào ví',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Quét QR ngân hàng ngay trong ứng dụng',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) =>
                    setState(() => _amount = int.tryParse(value) ?? 0),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.payments_outlined),
                  labelText: 'Số tiền muốn nạp',
                  suffixText: 'đ',
                  helperText: 'Từ 10.000đ đến 50.000.000đ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [50000, 100000, 200000, 500000].map((amount) {
                  final selected = _amount == amount;
                  return ChoiceChip(
                    label: Text(_money(amount.toDouble())),
                    selected: selected,
                    onSelected: (_) => _setAmount(amount),
                    selectedColor: AppColors.primary.withValues(alpha: .16),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : colors.outlineVariant,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: valid ? () => Navigator.pop(context, _amount) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Tạo mã QR'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerPayosQrDialog extends StatefulWidget {
  const _CustomerPayosQrDialog({required this.checkout});

  final PayosCheckout checkout;

  @override
  State<_CustomerPayosQrDialog> createState() => _CustomerPayosQrDialogState();
}

class _CustomerPayosQrDialogState extends State<_CustomerPayosQrDialog> {
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
      // PayOS có thể mất vài giây để gửi webhook xác nhận giao dịch.
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
    return AlertDialog(
      title: const Text('Quét QR để nạp ví'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                size: 230,
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancelling ? null : _cancelPayment,
          child: _cancelling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _cancelling
              ? null
              : () async {
                  final opened = await launchUrl(
                    Uri.parse(widget.checkout.checkoutUrl),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!context.mounted || opened) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Không mở được trang thanh toán.'),
                    ),
                  );
                },
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Mở thanh toán'),
        ),
      ],
    );
  }
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({
    required this.balance,
    required this.pendingWithdrawal,
    required this.onWithdraw,
    required this.onTopUp,
  });

  final double balance;
  final double pendingWithdrawal;
  final VoidCallback? onWithdraw;
  final VoidCallback? onTopUp;

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
              child: OutlinedButton.icon(
                onPressed: onTopUp,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF5CDCD0)),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Nạp tiền'),
              ),
            ),
            const SizedBox(height: 8),
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
