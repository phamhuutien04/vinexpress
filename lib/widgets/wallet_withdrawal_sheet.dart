import 'package:flutter/material.dart';

class WalletWithdrawalRequest {
  const WalletWithdrawalRequest({required this.amount});

  final double amount;
}

Future<WalletWithdrawalRequest?> showWalletWithdrawalSheet(
  BuildContext context, {
  required double balance,
}) {
  return showModalBottomSheet<WalletWithdrawalRequest>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WalletWithdrawalSheet(balance: balance),
  );
}

class _WalletWithdrawalSheet extends StatefulWidget {
  const _WalletWithdrawalSheet({required this.balance});
  final double balance;

  @override
  State<_WalletWithdrawalSheet> createState() => _WalletWithdrawalSheetState();
}

class _WalletWithdrawalSheetState extends State<_WalletWithdrawalSheet> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(
      _amount.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (amount == null || amount < 50000 || amount > widget.balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số tiền không hợp lệ hoặc vượt quá số dư ví.'),
        ),
      );
      return;
    }
    Navigator.pop(context, WalletWithdrawalRequest(amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Yêu cầu rút tiền',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text('Số dư khả dụng: ${_money(widget.balance)}'),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền rút',
                suffixText: 'đ',
                helperText: 'Tối thiểu 50.000đ',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tiền sẽ được chuyển đến tài khoản ngân hàng đã liên kết trong mục Tài khoản.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Gửi yêu cầu rút tiền'),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(dynamic value) {
  final number = (value as num?)?.round() ?? 0;
  return '${number.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
}
