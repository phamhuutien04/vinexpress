import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/wallet_service.dart';

class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _service = WalletService();
  final _formKey = GlobalKey<FormState>();
  final _bank = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountHolder = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _linked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bank.dispose();
    _accountNumber.dispose();
    _accountHolder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final account = await _service.getLinkedBankAccount();
      if (!mounted) return;
      if (account != null) {
        _bank.text = '${account['ngan_hang'] ?? ''}';
        _accountNumber.text = '${account['so_tai_khoan'] ?? ''}';
        _accountHolder.text = '${account['chu_tai_khoan'] ?? ''}';
      }
      setState(() => _linked = account != null);
    } on WalletServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _service.linkBankAccount(
        bankName: _bank.text.trim(),
        accountNumber: _accountNumber.text.trim(),
        accountHolder: _accountHolder.text.trim(),
      );
      if (!mounted) return;
      setState(() => _linked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu tài khoản ngân hàng.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on WalletServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Không được để trống' : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản ngân hàng')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color:
                                (_linked
                                        ? AppColors.success
                                        : AppColors.warning)
                                    .withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _linked
                                    ? Icons.verified_rounded
                                    : Icons.info_outline_rounded,
                                color: _linked
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _linked
                                      ? 'Tài khoản đã được liên kết với ví.'
                                      : 'Liên kết ngân hàng trước khi rút tiền.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _bank,
                          validator: _required,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Ngân hàng',
                            hintText: 'Ví dụ: MBBANK',
                            prefixIcon: Icon(Icons.account_balance_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _accountNumber,
                          validator: _required,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Số tài khoản',
                            prefixIcon: Icon(Icons.numbers_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _accountHolder,
                          validator: _required,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Tên chủ tài khoản',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _linked
                                ? 'Cập nhật liên kết'
                                : 'Liên kết ngân hàng',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
