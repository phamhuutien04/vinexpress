# VinExpress - Hướng dẫn Màu sắc Chủ đạo

## 🎨 Bảng màu VinFast Brand Identity

Ứng dụng VinExpress sử dụng hệ thống màu sắc dựa trên VinFast brand identity.

### Màu Chính (Primary Colors)

#### 1. Teal (Xanh Ngọc) - Màu Chủ Đạo
- **Hex**: `#00BFA5`
- **RGB**: `(0, 191, 165)`
- **Flutter**: `Color(0xFF00BFA5)`
- **Sử dụng**: Logo, buttons, links, focused borders, primary actions

#### 2. Cyan (Xanh Lơ Sáng) - Màu Phụ
- **Hex**: `#26C6DA`
- **RGB**: `(38, 198, 218)`
- **Flutter**: `Color(0xFF26C6DA)`
- **Sử dụng**: Gradient với màu teal, secondary actions, highlights

#### 3. Amber (Vàng) - Màu Nhấn
- **Hex**: `#FFC107`
- **RGB**: `(255, 193, 7)`
- **Flutter**: `Color(0xFFFFC107)`
- **Sử dụng**: Accents, badges, important notifications, "SM" trong logo

### Gradient Chính

```dart
LinearGradient(
  colors: [
    Color(0xFF00BFA5),  // Teal
    Color(0xFF26C6DA),  // Cyan
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)
```

### Màu Trung Tính (Neutral Colors)

- **Text Primary**: `#212121` (Xám đậm)
- **Text Secondary**: `#757575` (Xám trung bình)
- **Text Disabled**: `#BDBDBD` (Xám nhạt)
- **Background**: `#FAFAFA` (Trắng xám nhạt)
- **Border**: `#E0E0E0` (Xám border)

### Màu Ngữ Nghĩa (Semantic Colors)

- **Success**: `#4CAF50` (Xanh lá)
- **Warning**: `#FF9800` (Cam)
- **Error**: `#F44336` (Đỏ)
- **Info**: `#2196F3` (Xanh dương)

## 📋 Hướng dẫn Sử dụng

### 1. Import AppColors

```dart
import 'package:vinexpress/core/constants/app_colors.dart';
```

### 2. Sử dụng trong Code

```dart
// Màu đơn
Container(
  color: AppColors.primary,
)

// Gradient
Container(
  decoration: BoxDecoration(
    gradient: AppColors.primaryGradient,
  ),
)

// Border với màu primary
OutlineInputBorder(
  borderSide: BorderSide(color: AppColors.primary, width: 2),
)

// Shadow
BoxShadow(
  color: AppColors.primaryShadow,
  blurRadius: 8,
  offset: Offset(0, 4),
)
```

### 3. Theme Configuration

```dart
ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
  ),
)
```

## 🎯 Nguyên tắc Thiết kế

1. **Màu Chủ Đạo**: Luôn sử dụng `AppColors.primary` (#00BFA5) cho các thành phần quan trọng
2. **Gradient**: Áp dụng gradient teal-cyan cho buttons, cards nổi bật
3. **Màu Vàng**: Chỉ dùng cho accent, không dùng làm màu chính
4. **Contrast**: Đảm bảo text trên background màu teal là white để dễ đọc
5. **Consistency**: Giữ nguyên hệ thống màu trong toàn bộ ứng dụng

## ⚠️ Lưu ý Quan Trọng

- **KHÔNG** sử dụng màu đỏ (`Colors.red`) hoặc xanh dương đậm (`#0047AB`) - đây là màu cũ
- **LUÔN** sử dụng `AppColors.primary` thay vì hard-code màu
- **KIỂM TRA** accessibility contrast khi dùng màu teal với text
- **CẬP NHẬT** file này khi có thay đổi về brand identity

## 📱 Ví dụ Áp dụng

### Button Gradient
```dart
Container(
  decoration: BoxDecoration(
    gradient: AppColors.primaryGradient,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: AppColors.primaryShadow,
        blurRadius: 8,
        offset: Offset(0, 4),
      ),
    ],
  ),
  child: ElevatedButton(...),
)
```

### Input Field Focused
```dart
TextFormField(
  decoration: InputDecoration(
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.primary, width: 2),
    ),
  ),
)
```

### Icon Background
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.primary10, // 10% opacity
    shape: BoxShape.circle,
  ),
  child: Icon(
    Icons.check,
    color: AppColors.primary,
  ),
)
```

---

**Ngày cập nhật**: 2024
**Phiên bản**: 1.0.0
**Brand**: VinFast/VinExpress
