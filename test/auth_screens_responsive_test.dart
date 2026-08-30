import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinexpress/core/theme/app_theme.dart';
import 'package:vinexpress/screens/auth/login_screen.dart';
import 'package:vinexpress/screens/auth/register_screen.dart';

void main() {
  final sizes = <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1280, 800),
  ];

  for (final size in sizes) {
    testWidgets('đăng nhập hiển thị tốt ở ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chào mừng trở lại'), findsOneWidget);
      expect(find.text('Đăng nhập'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('đăng ký hiển thị tốt ở ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const RegisterScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tạo tài khoản khách hàng'), findsOneWidget);
      expect(find.text('Khách hàng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
