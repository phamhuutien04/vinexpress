import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/order_service.dart';
import '../../widgets/address_input.dart';
import 'invoice_preview_screen.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _senderName = TextEditingController(text: 'Nguyễn Minh Anh');
  final _senderPhone = TextEditingController(text: '090 123 4567');
  final _senderAddress = TextEditingController(
    text: '12 Nguyễn Huệ, Bến Nghé, Quận 1, TP.HCM',
  );
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _receiverAddress = TextEditingController();
  final _weight = TextEditingController(text: '1');
  final _itemValue = TextEditingController(text: '0');
  final _codAmount = TextEditingController(text: '0');
  final _note = TextEditingController();

  bool _cod = false;
  bool _isLoading = false;
  bool _calculatingFee = false;
  bool _feeCalculated = false;
  bool _truckDelivery = false;
  double? _quotedDistanceKm;
  double? _senderLatitude;
  double? _senderLongitude;
  final _orderService = OrderService();

  int _shippingFee = 0;
  Timer? _feeDebounce;
  int _feeRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    final customer = CustomerAuthService.currentCustomer;
    _senderName.text = customer?['ho_ten'] as String? ?? '';
    _senderPhone.text = customer?['so_dien_thoai'] as String? ?? '';
    _senderAddress.text = customer?['dia_chi'] as String? ?? '';
  }

  @override
  void dispose() {
    _feeDebounce?.cancel();
    for (final controller in [
      _senderName,
      _senderPhone,
      _senderAddress,
      _receiverName,
      _receiverPhone,
      _receiverAddress,
      _weight,
      _itemValue,
      _codAmount,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _money(int value) {
    final text = value.toString();
    return '${text.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (!_feeCalculated && !await _calculateFee()) return;
    setState(() => _isLoading = true);
    try {
      final order = await _orderService.createOrder(
        senderName: _senderName.text,
        senderPhone: _senderPhone.text,
        senderAddress: _senderAddress.text,
        receiverName: _receiverName.text,
        receiverPhone: _receiverPhone.text,
        receiverAddress: _receiverAddress.text,
        weight: double.parse(_weight.text),
        itemValue: double.tryParse(_itemValue.text) ?? 0,
        shippingFee: _shippingFee.toDouble(),
        cod: _cod ? (double.tryParse(_codAmount.text) ?? 0) : 0,
        note: _note.text,
        senderLatitude: _senderLatitude,
        senderLongitude: _senderLongitude,
      );
      if (!mounted) return;
      _showSuccess(order);
    } on OrderServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _calculateFee() async {
    if (_senderAddress.text.trim().isEmpty ||
        _receiverAddress.text.trim().isEmpty) {
      _showError('Vui lòng nhập đầy đủ địa chỉ gửi và nhận trước.');
      return false;
    }
    final requestVersion = _feeRequestVersion;
    setState(() => _calculatingFee = true);
    try {
      final quote = await _orderService.calculateShippingQuote(
        senderAddress: _senderAddress.text,
        receiverAddress: _receiverAddress.text,
        weight: double.tryParse(_weight.text) ?? 0,
        senderLatitude: _senderLatitude,
        senderLongitude: _senderLongitude,
      );
      if (!mounted || requestVersion != _feeRequestVersion) return false;
      setState(() {
        _shippingFee = quote.shippingFee.round();
        _feeCalculated = true;
        _truckDelivery = quote.vehicle == 'XE_TAI';
        _quotedDistanceKm = quote.distanceKm;
      });
      return true;
    } on OrderServiceException catch (error) {
      if (mounted) _showError(error.message);
      return false;
    } finally {
      if (mounted && requestVersion == _feeRequestVersion) {
        setState(() => _calculatingFee = false);
      }
    }
  }

  void _invalidateFee() {
    _feeRequestVersion++;
    if (!_feeCalculated && _shippingFee == 0 && !_calculatingFee) return;
    setState(() {
      _feeCalculated = false;
      _shippingFee = 0;
      _truckDelivery = false;
      _quotedDistanceKm = null;
      _calculatingFee = false;
    });
  }

  void _scheduleAutomaticFeeCalculation({bool immediately = false}) {
    _invalidateFee();
    _feeDebounce?.cancel();
    if (_senderAddress.text.trim().isEmpty ||
        _receiverAddress.text.trim().isEmpty) {
      return;
    }
    if (immediately) {
      _calculateFee();
    } else {
      _feeDebounce = Timer(const Duration(milliseconds: 900), _calculateFee);
    }
  }

  void _showSuccess(Map<String, dynamic> order) {
    final trackingCode = order['ma_van_don'] as String;
    final distance = ((order['khoang_cach_km'] as num?)?.toDouble() ?? 0)
        .toStringAsFixed(2)
        .replaceFirst('.', ',');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFE7F8F4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tạo đơn hàng thành công!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Mã vận đơn của bạn: $trackingCode',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Khoảng cách: $distance km',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Phí vận chuyển: ${_money(((order['phi_van_chuyen'] as num?)?.round() ?? _shippingFee))}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (order['phuong_tien'] == 'XE_TAI') ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (_) => InvoicePreviewScreen(order: order),
                      ),
                    );
                  },
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Xem / In hóa đơn'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(this.context, true);
                },
                child: const Text('Về trang chủ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tạo đơn hàng'),
            Text(
              'Giao nhanh, an tâm mọi hành trình',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Hỗ trợ',
            onPressed: () {},
            icon: const Icon(Icons.headset_mic_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
          children: [
            _ProgressHeader(),
            const SizedBox(height: 20),
            _SectionCard(
              icon: Icons.person_pin_circle_outlined,
              title: 'Thông tin người gửi',
              subtitle: 'Địa chỉ lấy hàng',
              child: Column(
                children: [
                  _Input(
                    controller: _senderName,
                    label: 'Họ và tên',
                    icon: Icons.person_outline,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  _Input(
                    controller: _senderPhone,
                    label: 'Số điện thoại',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  AddressInput(
                    controller: _senderAddress,
                    label: 'Địa chỉ lấy hàng',
                    hint: 'Chọn hoặc nhập địa chỉ lấy hàng',
                    includeSubArea: false,
                    allowCurrentLocation: true,
                    onCurrentLocationSelected: (latitude, longitude) {
                      _senderLatitude = latitude;
                      _senderLongitude = longitude;
                    },
                    onAddressChanged: () {
                      _senderLatitude = null;
                      _senderLongitude = null;
                      _scheduleAutomaticFeeCalculation();
                    },
                    onAddressSelected: () =>
                        _scheduleAutomaticFeeCalculation(immediately: true),
                    validator: _required,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.location_on_outlined,
              title: 'Thông tin người nhận',
              subtitle: 'Địa chỉ giao hàng',
              child: Column(
                children: [
                  _Input(
                    controller: _receiverName,
                    label: 'Họ và tên người nhận',
                    hint: 'Nhập tên người nhận',
                    icon: Icons.person_outline,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  _Input(
                    controller: _receiverPhone,
                    label: 'Số điện thoại',
                    hint: 'Nhập số điện thoại',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  AddressInput(
                    controller: _receiverAddress,
                    label: 'Địa chỉ giao hàng',
                    hint: 'Số nhà, tên đường, phường/xã...',
                    includeSubArea: false,
                    onAddressChanged: _scheduleAutomaticFeeCalculation,
                    onAddressSelected: () =>
                        _scheduleAutomaticFeeCalculation(immediately: true),
                    validator: _required,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.inventory_2_outlined,
              title: 'Thông tin kiện hàng',
              subtitle: 'Mô tả hàng cần giao',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Input(
                    controller: _weight,
                    label: 'Khối lượng (kg)',
                    icon: Icons.scale_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: (_) => _scheduleAutomaticFeeCalculation(),
                    validator: (value) {
                      final weight = double.tryParse(value ?? '');
                      return weight == null || weight <= 0
                          ? 'Khối lượng phải lớn hơn 0'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _Input(
                    controller: _itemValue,
                    label: 'Giá trị hàng hóa (đ)',
                    icon: Icons.sell_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    validator: _nonNegative,
                  ),
                  const SizedBox(height: 12),
                  _Input(
                    controller: _note,
                    label: 'Ghi chú cho tài xế',
                    hint: 'Ví dụ: Hàng dễ vỡ, gọi trước khi giao...',
                    icon: Icons.notes_outlined,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Thu hộ tiền (COD)'),
                    subtitle: const Text('Tài xế thu tiền khi giao hàng'),
                    value: _cod,
                    activeThumbColor: AppColors.primary,
                    onChanged: (value) => setState(() => _cod = value),
                  ),
                  if (_cod) ...[
                    const SizedBox(height: 4),
                    _Input(
                      controller: _codAmount,
                      label: 'Số tiền cần thu hộ (đ)',
                      icon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      validator: (value) {
                        if (!_cod) return null;
                        final amount = double.tryParse(value ?? '');
                        return amount == null || amount <= 0
                            ? 'Số tiền COD phải lớn hơn 0'
                            : null;
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SummaryCard(
              shippingFee: _shippingFee,
              codFee: 0,
              money: _money,
              feeCalculated: _feeCalculated,
              calculating: _calculatingFee,
              truckDelivery: _truckDelivery,
              distanceKm: _quotedDistanceKm,
              weight: double.tryParse(_weight.text) ?? 0,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tổng thanh toán',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      _feeCalculated ? _money(_shippingFee) : 'Chưa tính phí',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isLoading || _calculatingFee ? null : _submit,
                icon: const Icon(Icons.arrow_forward_rounded),
                iconAlignment: IconAlignment.end,
                label: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Tạo đơn'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Vui lòng nhập thông tin' : null;

  String? _nonNegative(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || number < 0 ? 'Giá trị không hợp lệ' : null;
  }
}

class _ProgressHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          _ProgressStep(number: '1', label: 'Thông tin', active: true),
          Expanded(child: Divider(color: Colors.white54, thickness: 2)),
          _ProgressStep(number: '2', label: 'Xác nhận'),
          Expanded(child: Divider(color: Colors.white54, thickness: 2)),
          _ProgressStep(number: '3', label: 'Hoàn tất'),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.number,
    required this.label,
    this.active = false,
  });
  final String number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active ? Colors.white : Colors.white24,
          child: Text(
            number,
            style: TextStyle(
              color: active ? AppColors.primary : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: .7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.primary10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.shippingFee,
    required this.codFee,
    required this.money,
    required this.feeCalculated,
    required this.calculating,
    required this.truckDelivery,
    required this.distanceKm,
    required this.weight,
  });
  final int shippingFee;
  final int codFee;
  final String Function(int) money;
  final bool feeCalculated;
  final bool calculating;
  final bool truckDelivery;
  final double? distanceKm;
  final double weight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary10,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                'Chi phí dự kiến',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _priceRow(
            'Phí vận chuyển',
            feeCalculated ? money(shippingFee) : 'Chưa tính',
          ),
          if (feeCalculated && distanceKm != null) ...[
            const SizedBox(height: 8),
            _priceRow(
              'Khoảng cách',
              '${distanceKm!.toStringAsFixed(2).replaceFirst('.', ',')} km',
            ),
            if (truckDelivery) ...[
              const SizedBox(height: 8),
              _priceRow(
                'Cân nặng tính phí',
                weight < 1 ? 'Miễn phí' : '${weight.floor()} kg',
              ),
            ],
          ],
          if (codFee > 0) ...[
            const SizedBox(height: 8),
            _priceRow('Phí thu hộ', money(codFee)),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          _priceRow(
            'Tổng cộng',
            feeCalculated ? money(shippingFee + codFee) : 'Chưa tính',
            strong: true,
          ),
          if (calculating) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text(
              'Đang tự động tính quãng đường và phí...',
              style: TextStyle(fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            truckDelivery
                ? 'Phí xe tải gồm phí cơ bản và phí theo mỗi kg nguyên được cấu hình trong database; dưới 1 kg không tính thêm phí cân nặng.'
                : 'Đơn xe máy ≤ 50 km được tính theo số km và biểu phí hiện tại do quản trị viên cấu hình.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool strong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: strong ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: strong ? AppColors.primary : null,
          ),
        ),
      ],
    );
  }
}
