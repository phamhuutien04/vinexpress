import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinexpress/core/theme/app_theme.dart';
import 'package:vinexpress/screens/customer/create_order_screen.dart';

void main() {
  for (final size in <Size>[const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('màn tạo đơn không bị thanh thanh toán che ở $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CreateOrderScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thông tin người gửi'), findsOneWidget);
      expect(find.text('Tổng thanh toán'), findsOneWidget);
      expect(find.text('Tạo đơn'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Tổng thanh toán')).dy,
        greaterThan(size.height * .75),
      );
      final exception = tester.takeException();
      expect(exception, isNull);
    });
  }
}
