import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinexpress/widgets/shipper_income_chart.dart';

void main() {
  test('groups delivered income by calendar day and compares prior week', () {
    final trend = calculateShipperIncomeTrend([
      {'ngay_giao_hang': '2026-10-03T09:00:00', 'tien_shipper': 12000},
      {'ngay_giao_hang': '2026-10-03T15:00:00', 'tien_shipper': 8000},
      {'ngay_giao_hang': '2026-09-27T12:00:00', 'tien_shipper': 10000},
      {'ngay_giao_hang': '2026-09-26T12:00:00', 'tien_shipper': 5000},
      {'ngay_giao_hang': '2026-09-20T12:00:00', 'tien_shipper': 9000},
      {'ngay_giao_hang': '2026-10-04T12:00:00', 'tien_shipper': 100000},
      {'ngay_giao_hang': 'invalid', 'tien_shipper': 100000},
    ], now: DateTime(2026, 10, 3));

    expect(trend.total, 30000);
    expect(trend.orderCount, 3);
    expect(trend.days.first.date, DateTime(2026, 9, 27));
    expect(trend.days.first.amount, 10000);
    expect(trend.days.last.amount, 20000);
    expect(trend.days.last.orderCount, 2);
    expect(trend.previousTotal, 14000);
  });

  test('filters current month, year and a custom inclusive date range', () {
    final entries = [
      {'ngay_giao_hang': '2026-01-12T09:00:00', 'tien_shipper': 10000},
      {'ngay_giao_hang': '2026-09-30T09:00:00', 'tien_shipper': 20000},
      {'ngay_giao_hang': '2026-10-01T09:00:00', 'tien_shipper': 30000},
      {'ngay_giao_hang': '2026-10-03T09:00:00', 'tien_shipper': 40000},
    ];
    final now = DateTime(2026, 10, 3);

    final month = calculateShipperIncomeTrend(
      entries,
      now: now,
      period: ShipperIncomePeriod.month,
    );
    expect(month.total, 70000);
    expect(month.previousTotal, 20000);
    expect(month.start, DateTime(2026, 10));

    final year = calculateShipperIncomeTrend(
      entries,
      now: now,
      period: ShipperIncomePeriod.year,
    );
    expect(year.total, 100000);
    expect(year.days.length, 12);
    expect(year.days[9].amount, 70000);

    final custom = calculateShipperIncomeTrend(
      entries,
      now: now,
      period: ShipperIncomePeriod.custom,
      from: DateTime(2026, 9, 30),
      to: DateTime(2026, 10, 1),
    );
    expect(custom.total, 50000);
    expect(custom.orderCount, 2);
    expect(custom.days.length, 2);
  });

  test('shows today by four-hour intervals and compares yesterday', () {
    final trend = calculateShipperIncomeTrend(
      [
        {'ngay_giao_hang': '2026-10-02T20:00:00', 'tien_shipper': 5000},
        {'ngay_giao_hang': '2026-10-03T00:30:00', 'tien_shipper': 10000},
        {'ngay_giao_hang': '2026-10-03T17:00:00', 'tien_shipper': 20000},
      ],
      now: DateTime(2026, 10, 3),
      period: ShipperIncomePeriod.day,
    );

    expect(trend.total, 30000);
    expect(trend.previousTotal, 5000);
    expect(trend.days.length, 6);
    expect(trend.days.first.label, '00h');
    expect(trend.days.first.amount, 10000);
    expect(trend.days[4].amount, 20000);
  });

  testWidgets('shows chart summary and an empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShipperIncomeChart(
            now: DateTime(2026, 10, 3),
            entries: const [
              {'ngay_giao_hang': '2026-10-03T09:00:00', 'tien_shipper': 12000},
            ],
          ),
        ),
      ),
    );

    expect(find.text('Phân tích thu nhập'), findsOneWidget);
    expect(find.text('12.000đ từ 1 đơn đã giao'), findsOneWidget);
    expect(find.text('T7'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShipperIncomeChart(
            now: DateTime(2026, 10, 3),
            entries: const [],
          ),
        ),
      ),
    );
    expect(find.text('Chưa có đơn giao trong khoảng ngày này'), findsOneWidget);
  });

  testWidgets('switches chart totals when selecting month and year', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShipperIncomeChart(
            now: DateTime(2026, 10, 3),
            entries: const [
              {'ngay_giao_hang': '2026-01-12T09:00:00', 'tien_shipper': 10000},
              {'ngay_giao_hang': '2026-10-03T09:00:00', 'tien_shipper': 20000},
            ],
          ),
        ),
      ),
    );
    expect(find.text('20.000đ từ 1 đơn đã giao'), findsOneWidget);
    await tester.tap(find.text('Năm'));
    await tester.pumpAndSettle();
    expect(find.text('30.000đ từ 2 đơn đã giao'), findsOneWidget);
    await tester.tap(find.text('Tháng'));
    await tester.pumpAndSettle();
    expect(find.text('20.000đ từ 1 đơn đã giao'), findsOneWidget);
    await tester.tap(find.text('Trong ngày'));
    await tester.pumpAndSettle();
    expect(find.text('00h'), findsOneWidget);
  });
}
