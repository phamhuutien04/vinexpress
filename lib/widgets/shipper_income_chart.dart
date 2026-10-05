import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

enum ShipperIncomePeriod { day, week, month, year, custom }

class ShipperDailyIncome {
  const ShipperDailyIncome({
    required this.date,
    required this.amount,
    required this.orderCount,
    required this.label,
  });
  final DateTime date;
  final double amount;
  final int orderCount;
  final String label;
}

class ShipperIncomeTrend {
  const ShipperIncomeTrend({
    required this.days,
    required this.previousTotal,
    required this.start,
    required this.end,
  });
  final List<ShipperDailyIncome> days;
  final double previousTotal;
  final DateTime start;
  final DateTime end;
  double get total => days.fold(0, (sum, day) => sum + day.amount);
  int get orderCount => days.fold(0, (sum, day) => sum + day.orderCount);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

ShipperIncomeTrend calculateShipperIncomeTrend(
  List<Map<String, dynamic>> entries, {
  DateTime? now,
  ShipperIncomePeriod period = ShipperIncomePeriod.week,
  DateTime? from,
  DateTime? to,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final start = switch (period) {
    ShipperIncomePeriod.day => today,
    ShipperIncomePeriod.week => DateTime(
      today.year,
      today.month,
      today.day - 6,
    ),
    ShipperIncomePeriod.month => DateTime(today.year, today.month),
    ShipperIncomePeriod.year => DateTime(today.year),
    ShipperIncomePeriod.custom => _dateOnly(from ?? today),
  };
  final end = period == ShipperIncomePeriod.custom
      ? _dateOnly(to ?? today)
      : today;
  final duration = _daysBetween(start, end) + 1;
  if (duration <= 0) {
    return ShipperIncomeTrend(
      days: const [],
      previousTotal: 0,
      start: start,
      end: end,
    );
  }
  final bucketCount = switch (period) {
    ShipperIncomePeriod.day => 6,
    ShipperIncomePeriod.year => 12,
    _ => duration.clamp(1, 7),
  };
  final amounts = List<double>.filled(bucketCount, 0);
  final counts = List<int>.filled(bucketCount, 0);
  var previousTotal = 0.0;

  for (final entry in entries) {
    final deliveredAt = DateTime.tryParse(
      '${entry['ngay_giao_hang'] ?? ''}',
    )?.toLocal();
    final rawAmount = entry['tien_shipper'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse('$rawAmount');
    if (deliveredAt == null ||
        amount == null ||
        !amount.isFinite ||
        amount < 0) {
      continue;
    }
    final dayIndex = _daysBetween(start, _dateOnly(deliveredAt));
    if (dayIndex >= 0 && dayIndex < duration) {
      final bucket = switch (period) {
        ShipperIncomePeriod.day => deliveredAt.hour ~/ 4,
        ShipperIncomePeriod.year => deliveredAt.month - 1,
        _ => (dayIndex * bucketCount ~/ duration).clamp(0, bucketCount - 1),
      };
      amounts[bucket] += amount;
      counts[bucket]++;
    } else if (dayIndex >= -duration && dayIndex < 0) {
      previousTotal += amount;
    }
  }

  return ShipperIncomeTrend(
    days: List.generate(bucketCount, (index) {
      if (period == ShipperIncomePeriod.day) {
        return ShipperDailyIncome(
          date: DateTime(today.year, today.month, today.day, index * 4),
          amount: amounts[index],
          orderCount: counts[index],
          label: '${(index * 4).toString().padLeft(2, '0')}h',
        );
      }
      if (period == ShipperIncomePeriod.year) {
        return ShipperDailyIncome(
          date: DateTime(today.year, index + 1),
          amount: amounts[index],
          orderCount: counts[index],
          label: 'T${index + 1}',
        );
      }
      final firstDay = index * duration ~/ bucketCount;
      final nextDay = (index + 1) * duration ~/ bucketCount;
      final bucketStart = DateTime(
        start.year,
        start.month,
        start.day + firstDay,
      );
      final bucketEnd = DateTime(
        start.year,
        start.month,
        start.day + nextDay - 1,
      );
      final label = period == ShipperIncomePeriod.week
          ? switch (bucketStart.weekday) {
              DateTime.monday => 'T2',
              DateTime.tuesday => 'T3',
              DateTime.wednesday => 'T4',
              DateTime.thursday => 'T5',
              DateTime.friday => 'T6',
              DateTime.saturday => 'T7',
              _ => 'CN',
            }
          : nextDay - firstDay > 1
          ? '${bucketStart.day}–${bucketEnd.day}'
          : '${bucketStart.day}/${bucketStart.month}';
      return ShipperDailyIncome(
        date: bucketStart,
        amount: amounts[index],
        orderCount: counts[index],
        label: label,
      );
    }),
    previousTotal: previousTotal,
    start: start,
    end: end,
  );
}

class ShipperIncomeChart extends StatefulWidget {
  const ShipperIncomeChart({
    super.key,
    required this.entries,
    this.errorMessage,
    this.now,
  });
  final List<Map<String, dynamic>> entries;
  final String? errorMessage;
  final DateTime? now;

  @override
  State<ShipperIncomeChart> createState() => _ShipperIncomeChartState();
}

class _ShipperIncomeChartState extends State<ShipperIncomeChart> {
  ShipperIncomePeriod _period = ShipperIncomePeriod.week;
  DateTimeRange? _customRange;

  Future<void> _chooseRange() async {
    final today = _dateOnly(widget.now ?? DateTime.now());
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: DateTime(today.year, today.month, today.day - 6),
            end: today,
          ),
      helpText: 'Chọn khoảng ngày thu nhập',
      saveText: 'Áp dụng',
    );
    if (selected != null && mounted) {
      setState(() {
        _customRange = selected;
        _period = ShipperIncomePeriod.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trend = calculateShipperIncomeTrend(
      widget.entries,
      now: widget.now,
      period: _period,
      from: _customRange?.start,
      to: _customRange?.end,
    );
    final colors = Theme.of(context).colorScheme;
    final maxAmount = trend.days.fold<double>(
      0,
      (max, day) => day.amount > max ? day.amount : max,
    );
    final comparison = trend.previousTotal > 0
        ? (trend.total - trend.previousTotal) / trend.previousTotal * 100
        : null;
    final rangeLabel =
        '${trend.start.day}/${trend.start.month}/${trend.start.year} – '
        '${trend.end.day}/${trend.end.month}/${trend.end.year}';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Phân tích thu nhập',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.bar_chart_rounded, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (period, label) in [
                  (ShipperIncomePeriod.day, 'Trong ngày'),
                  (ShipperIncomePeriod.week, 'Tuần'),
                  (ShipperIncomePeriod.month, 'Tháng'),
                  (ShipperIncomePeriod.year, 'Năm'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _period == period,
                    onSelected: (_) => setState(() => _period = period),
                    selectedColor: AppColors.primary.withValues(alpha: .16),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 18),
                  label: const Text('Từ ngày – đến ngày'),
                  backgroundColor: _period == ShipperIncomePeriod.custom
                      ? AppColors.primary.withValues(alpha: .16)
                      : null,
                  onPressed: _chooseRange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              rangeLabel,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              '${_money(trend.total)} từ ${trend.orderCount} đơn đã giao',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            if (widget.errorMessage != null)
              Text(
                'Không tải được dữ liệu thu nhập.',
                style: TextStyle(color: colors.error),
              )
            else if (trend.orderCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Chưa có đơn giao trong khoảng ngày này',
                    style: TextStyle(color: colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < trend.days.length; index++)
                    Expanded(
                      child: _IncomeBar(
                        day: trend.days[index],
                        maximum: maxAmount,
                        isLast: index == trend.days.length - 1,
                        period: _period,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                comparison == null
                    ? 'Chưa có thu nhập ở kỳ trước để so sánh'
                    : '${comparison >= 0 ? 'Tăng' : 'Giảm'} ${comparison.abs().toStringAsFixed(0)}% so với khoảng trước đó',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IncomeBar extends StatelessWidget {
  const _IncomeBar({
    required this.day,
    required this.maximum,
    required this.isLast,
    required this.period,
  });
  final ShipperDailyIncome day;
  final double maximum;
  final bool isLast;
  final ShipperIncomePeriod period;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = day.amount == 0 || maximum == 0
        ? 0.0
        : (day.amount / maximum * 100).clamp(7.0, 100.0);
    final detail = '${day.label}: ${_money(day.amount)}, ${day.orderCount} đơn';
    return Tooltip(
      message: detail,
      child: Semantics(
        label: detail,
        child: Column(
          children: [
            SizedBox(
              height: 104,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: period == ShipperIncomePeriod.year ? 12 : 22,
                  height: height,
                  decoration: BoxDecoration(
                    color: isLast
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: .48),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              day.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isLast ? colors.onSurface : colors.onSurfaceVariant,
                fontSize: period == ShipperIncomePeriod.year ? 10 : 11,
                fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(double amount) {
  final formatted = amount.round().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return '$formattedđ';
}
