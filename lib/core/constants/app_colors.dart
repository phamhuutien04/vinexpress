import 'package:flutter/material.dart';

/// Màu sắc chủ đạo của ứng dụng VinExpress
/// Dựa theo bảng màu VinFast brand identity
class AppColors {
  AppColors._(); // Private constructor để prevent instantiation

  // === BRAND COLORS - VinFast Identity ===
  
  /// Màu xanh ngọc chính (Teal) - Màu chủ đạo của VinFast
  /// Hex: #00BFA5
  /// RGB: (0, 191, 165)
  static const Color primary = Color(0xFF00BFA5);
  
  /// Màu xanh cyan phụ - Dùng cho gradient và accents
  /// Hex: #26C6DA
  /// RGB: (38, 198, 218)
  static const Color secondary = Color(0xFF26C6DA);
  
  /// Màu vàng VinFast - Màu nhấn (accent color)
  /// Hex: #FFC107
  /// RGB: (255, 193, 7)
  static const Color accent = Color(0xFFFFC107);
  
  // === GRADIENT COLORS ===
  
  /// Gradient chính từ teal đến cyan
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  /// Gradient vàng cho các highlight đặc biệt
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFFA726), accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // === NEUTRAL COLORS ===
  
  /// Màu trắng
  static const Color white = Color(0xFFFFFFFF);
  
  /// Màu đen
  static const Color black = Color(0xFF000000);
  
  /// Màu xám đậm cho text chính
  static const Color textPrimary = Color(0xFF212121);
  
  /// Màu xám trung bình cho text phụ
  static const Color textSecondary = Color(0xFF757575);
  
  /// Màu xám nhạt cho text disabled
  static const Color textDisabled = Color(0xFFBDBDBD);
  
  /// Màu background xám nhạt
  static const Color background = Color(0xFFFAFAFA);
  
  /// Màu border/divider
  static const Color border = Color(0xFFE0E0E0);
  
  // === SEMANTIC COLORS ===
  
  /// Màu thành công (success)
  static const Color success = Color(0xFF4CAF50);
  
  /// Màu cảnh báo (warning)
  static const Color warning = Color(0xFFFF9800);
  
  /// Màu lỗi (error)
  static const Color error = Color(0xFFF44336);
  
  /// Màu thông tin (info)
  static const Color info = Color(0xFF2196F3);
  
  // === SHADOW COLORS ===
  
  /// Shadow cho primary color
  static Color get primaryShadow => primary.withValues(alpha: 0.3);
  
  /// Shadow cho secondary color
  static Color get secondaryShadow => secondary.withValues(alpha: 0.3);
  
  /// Shadow mặc định
  static Color get defaultShadow => const Color(0xFF000000).withValues(alpha: 0.1);
  
  // === OPACITY VARIANTS ===
  
  /// Primary với độ trong suốt 10%
  static Color get primary10 => primary.withValues(alpha: 0.1);
  
  /// Primary với độ trong suốt 20%
  static Color get primary20 => primary.withValues(alpha: 0.2);
  
  /// Primary với độ trong suốt 50%
  static Color get primary50 => primary.withValues(alpha: 0.5);
}
