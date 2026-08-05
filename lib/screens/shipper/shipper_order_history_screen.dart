import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/shipper_service.dart';

enum _HistoryPeriod { day, month, year, range }

class ShipperOrderHistoryScreen extends StatefulWidget {
  const ShipperOrderHistoryScreen({super.key});

  @override
  State<ShipperOrderHistoryScreen> createState() =>
      _ShipperOrderHistoryScreenState();
}

class _ShipperOrderHistoryScreenState extends State<ShipperOrderHistoryScreen> {
  final _service = ShipperService();
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  _HistoryPeriod _period = _HistoryPeriod.day;
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _selectedRange;

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
      final orders = await _service.getDeliveredOrderHistory();
      if (mounted) setState(() => _orders = orders);
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    return _orders.where((order) {
      final deliveredAt = _parseDate(order['ngay_giao_hang']);
      if (deliveredAt == null) return false;
      return switch (_period) {
        _HistoryPeriod.day => _sameDay(deliveredAt, _selectedDate),
        _HistoryPeriod.month =>
          deliveredAt.year == _selectedDate.year &&
              deliveredAt.month == _selectedDate.month,
        _HistoryPeriod.year => deliveredAt.year == _selectedDate.year,
        _HistoryPeriod.range => _isInRange(deliveredAt, _selectedRange),
      };
    }).toList();
  }

  double get _totalIncome => _filteredOrders.fold(
    0,
    (total, order) =>
        total + ((order['tien_shipper'] as num?)?.toDouble() ?? 0),
  );

  String get _periodLabel => switch (_period) {
    _HistoryPeriod.day => 'Ngày ${_formatDate(_selectedDate)}',
    _HistoryPeriod.month =>
      'Tháng ${_selectedDate.month}/${_selectedDate.year}',
    _HistoryPeriod.year => 'Năm ${_selectedDate.year}',
    _HistoryPeriod.range =>
      _selectedRange == null
          ? 'Khoảng ngày tùy chỉnh'
          : '${_formatDate(_selectedRange!.start)} – '
                '${_formatDate(_selectedRange!.end)}',
  };

  Future<void> _selectPeriodValue() async {
    final now = DateTime.now();
    if (_period == _HistoryPeriod.range) {
      final range = await showDateRangePicker(
        context: context,
        initialDateRange: _selectedRange,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1, 12, 31),
        helpText: 'Chọn từ ngày đến ngày',
        cancelText: 'Hủy',
        confirmText: 'Áp dụng',
        saveText: 'Áp dụng',
      );
      if (range != null && mounted) setState(() => _selectedRange = range);
      return;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: switch (_period) {
        _HistoryPeriod.day => 'Chọn ngày cần tổng kết',
        _HistoryPeriod.month => 'Chọn một ngày trong tháng cần tổng kết',
        _HistoryPeriod.year => 'Chọn một ngày trong năm cần tổng kết',
        _ => 'Chọn thời gian',
      },
      cancelText: 'Hủy',
      confirmText: 'Chọn',
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  Future<void> _changePeriod(_HistoryPeriod value) async {
    final today = DateTime.now();
    setState(() {
      _period = value;
      if (value != _HistoryPeriod.range) {
        _selectedDate = today;
      }
      if (value == _HistoryPeriod.range && _selectedRange == null) {
        _selectedRange = DateTimeRange(start: today, end: today);
      }
    });
    if (value == _HistoryPeriod.range) await _selectPeriodValue();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IncomeSummary(
            total: _totalIncome,
            orderCount: _filteredOrders.length,
            periodLabel: _periodLabel,
          ),
          const SizedBox(height: 14),
          _PeriodFilter(
            period: _period,
            periodLabel: _periodLabel,
            onPeriodChanged: _changePeriod,
            onSelectValue: _selectPeriodValue,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Đơn đã giao',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('${_filteredOrders.length} đơn'),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            _MessageState(icon: Icons.error_outline_rounded, message: _error!)
          else if (_filteredOrders.isEmpty)
            _MessageState(
              icon: Icons.history_rounded,
              message: 'Không có đơn giao trong $_periodLabel',
            )
          else
            ..._filteredOrders.map(
              (order) => _DeliveredOrderCard(order: order),
            ),
        ],
      ),
    );
  }
}

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({
    required this.period,
    required this.periodLabel,
    required this.onPeriodChanged,
    required this.onSelectValue,
  });

  final _HistoryPeriod period;
  final String periodLabel;
  final ValueChanged<_HistoryPeriod> onPeriodChanged;
  final VoidCallback onSelectValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _HistoryPeriod.values.map((value) {
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    selected: period == value,
                    label: Text(_periodName(value)),
                    onSelected: (_) => onPeriodChanged(value),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          if (period == _HistoryPeriod.range)
            OutlinedButton.icon(
              onPressed: onSelectValue,
              icon: const Icon(Icons.date_range_rounded),
              label: Text(periodLabel),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      periodLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomeSummary extends StatelessWidget {
  const _IncomeSummary({
    required this.total,
    required this.orderCount,
    required this.periodLabel,
  });

  final double total;
  final int orderCount;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tổng thu nhập đã ghi nhận',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            _money(total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$orderCount đơn giao thành công',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(periodLabel, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _DeliveredOrderCard extends StatelessWidget {
  const _DeliveredOrderCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order['ma_van_don'] ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _money(order['tien_shipper']),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line(Icons.my_location_rounded, '${order['nguoi_gui_dia_chi']}'),
            _line(Icons.flag_rounded, '${order['nguoi_nhan_dia_chi']}'),
            if (_parseDate(order['ngay_giao_hang']) case final date?)
              _line(
                Icons.schedule_rounded,
                'Giao lúc ${_formatDateTime(date)}',
              ),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sàn ${_percent(order['phan_tram_san'])}: '
                    '${_money(order['tien_san'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  order['trang_thai_thanh_toan'] == 'DA_THANH_TOAN'
                      ? 'Đã thanh toán'
                      : 'Chưa thanh toán',
                  style: TextStyle(
                    color: order['trang_thai_thanh_toan'] == 'DA_THANH_TOAN'
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textDisabled),
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

String _percent(dynamic value) {
  final number = (value as num?)?.toDouble() ?? 0;
  return number == number.roundToDouble()
      ? '${number.round()}%'
      : '${number.toStringAsFixed(1)}%';
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse('$value')?.toLocal();
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${_formatDate(value)} ${two(value.hour)}:${two(value.minute)}';
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

bool _isInRange(DateTime value, DateTimeRange? range) {
  if (range == null) return false;
  final day = DateTime(value.year, value.month, value.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !day.isBefore(start) && !day.isAfter(end);
}

String _periodName(_HistoryPeriod value) => switch (value) {
  _HistoryPeriod.day => 'Ngày',
  _HistoryPeriod.month => 'Tháng',
  _HistoryPeriod.year => 'Năm',
  _HistoryPeriod.range => 'Tùy chỉnh',
};
