import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../services/payos_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/wallet_withdrawal_sheet.dart';

class EmployeeWalletScreen extends StatefulWidget {
  const EmployeeWalletScreen({super.key});

  @override
  State<EmployeeWalletScreen> createState() => _EmployeeWalletScreenState();
}

class _EmployeeWalletScreenState extends State<EmployeeWalletScreen> {
  final _service = WalletService();
  final _payosService = PayosService();
  Map<String, dynamic> _wallet = {};
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  RealtimeChannel? _walletChannel;
  Timer? _realtimeDebounce;

  double get _balance => (_wallet['so_du'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeWalletRealtime();
  }

  void _subscribeWalletRealtime() {
    _walletChannel = Supabase.instance.client
        .channel(
          'employee-wallet-${Supabase.instance.client.auth.currentUser?.id}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vi',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'giao_dich_vi',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .subscribe();
  }

  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(
      const Duration(milliseconds: 250),
      _refreshSilently,
    );
  }

  Future<void> _refreshSilently() async {
    if (!mounted || _loading || _refreshing) return;
    _refreshing = true;
    try {
      final results = await Future.wait([
        _service.getWalletInfo(),
        _service.getTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as Map<String, dynamic>;
        _transactions = results[1] as List<Map<String, dynamic>>;
        _error = null;
      });
    } on WalletServiceException {
      // Giữ số dư đang thấy; Realtime sẽ thử lại khi có thay đổi tiếp theo.
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
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => const _EmployeeTopUpDialog(),
    );
    if (amount == null) return;
    try {
      final checkout = await _payosService.createWalletTopUp(
        amount: amount.round(),
      );
      if (!mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EmployeePayosQrDialog(checkout: checkout),
      );
      if (paid == true && mounted) await _load();
    } on PayosServiceException catch (error) {
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

class _EmployeeTopUpDialog extends StatefulWidget {
  const _EmployeeTopUpDialog();

  @override
  State<_EmployeeTopUpDialog> createState() => _EmployeeTopUpDialogState();
}

class _EmployeeTopUpDialogState extends State<_EmployeeTopUpDialog> {
  final _controller = TextEditingController();

  double? get _amount =>
      double.tryParse(_controller.text.replaceAll(RegExp(r'[^0-9]'), ''));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = _amount;
    if (amount == null || amount < 10000) return;
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yêu cầu nạp ví'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Số tiền nạp',
        suffixText: 'đ',
        helperText: 'Tối thiểu 10.000đ',
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: (_amount ?? 0) >= 10000 ? _submit : null,
        child: const Text('Gửi yêu cầu'),
      ),
    ],
  );
}

class _EmployeePayosQrDialog extends StatefulWidget {
  const _EmployeePayosQrDialog({required this.checkout});

  final PayosCheckout checkout;

  @override
  State<_EmployeePayosQrDialog> createState() => _EmployeePayosQrDialogState();
}

class _EmployeePayosQrDialogState extends State<_EmployeePayosQrDialog> {
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
      if (await _payosService.isPaymentCompleted(widget.checkout.orderCode) &&
          mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      // Webhook ngân hàng có thể đến chậm; tiếp tục kiểm tra ở lần sau.
    } finally {
      _checking = false;
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await _payosService.cancelWalletTopUp(widget.checkout.orderCode);
      if (mounted) Navigator.of(context).pop(false);
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
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Quét QR để nạp ví',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text('Thanh toán ${_employeeMoney(widget.checkout.amount)}'),
              const SizedBox(height: 18),
              if (qrCode != null && qrCode.isNotEmpty)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: qrCode,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Icon(Icons.qr_code_2_rounded, size: 96),
                ),
              const SizedBox(height: 14),
              const Text(
                'QR sẽ tự đóng khi thanh toán thành công và ví được cộng tiền.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelling ? null : _cancel,
                      child: const Text('Hủy'),
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
                                const SnackBar(
                                  content: Text(
                                    'Không mở được trang thanh toán.',
                                  ),
                                ),
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

String _employeeMoney(num value) {
  final formatted = value.round().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return '$formattedđ';
}
