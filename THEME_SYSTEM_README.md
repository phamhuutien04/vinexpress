# 🌓 VinExpress - Hệ Thống Theme Sáng/Tối

## ✅ Đã Setup Hoàn tất

### 📁 Files đã tạo:

1. **`lib/core/theme/theme_provider.dart`**
   - Provider quản lý theme mode (Light/Dark/System)
   - Lưu preference vào SharedPreferences
   - Methods: `toggleTheme()`, `setThemeMode()`, `isDarkMode`, `isLightMode`

2. **`lib/core/theme/app_theme.dart`**
   - Theme definitions cho Light và Dark mode
   - Tất cả colors, text styles, button styles, input styles
   - Tuân thủ VinFast brand colors

3. **`lib/widgets/theme_toggle_button.dart`**
   - `ThemeToggleButton`: Icon button để toggle
   - `ThemeToggleSwitch`: Switch tile cho settings
   - `ThemeModeSelector`: Radio buttons chọn System/Light/Dark

4. **`.kiro/steering/theme-system.md`**
   - Hướng dẫn chi tiết về theme system
   - Auto-include khi code
   - Quy tắc bắt buộc khi tạo màn hình mới

## 🚀 Cách Sử dụng

### 1. Toggle Theme trong AppBar

```dart
AppBar(
  actions: [
    ThemeToggleButton(), // Icon button
  ],
)
```

### 2. Trong Settings Screen

```dart
// Switch đơn giản
ThemeToggleSwitch()

// Hoặc selector đầy đủ
ThemeModeSelector()
```

### 3. Đọc Theme State

```dart
final themeProvider = Provider.of<ThemeProvider>(context);

if (themeProvider.isDarkMode) {
  // Dark mode logic
}

// Toggle
themeProvider.toggleTheme();

// Set specific
themeProvider.setThemeMode(ThemeMode.dark);
```

### 4. Sử dụng Theme Colors

```dart
// Background
Container(
  color: Theme.of(context).scaffoldBackgroundColor,
)

// Text
Text(
  'Hello',
  style: Theme.of(context).textTheme.titleLarge,
)

// Card
Card(
  color: Theme.of(context).cardColor,
)

// Icon
Icon(
  Icons.settings,
  color: Theme.of(context).iconTheme.color,
)
```

## ⚠️ Quy tắc BẮT BUỘC

### ❌ KHÔNG làm:
```dart
// KHÔNG hard-code màu
Container(color: Colors.white)
Text('Hi', style: TextStyle(color: Colors.black))
```

### ✅ PHẢI làm:
```dart
// Dùng Theme context
Container(color: Theme.of(context).scaffoldBackgroundColor)
Text('Hi', style: Theme.of(context).textTheme.bodyLarge)
```

## 🎨 Màu Themes

### Light Mode
- Background: `#FFFFFF` 
- Surface: `#FAFAFA`
- Text: `#212121`
- Primary: `#00BFA5` (Teal - VinFast)

### Dark Mode
- Background: `#121212`
- Surface: `#1E1E1E`
- Text: `#FFFFFF`
- Primary: `#00BFA5` (Teal - giữ nguyên)

## 📋 Checklist khi tạo màn hình mới

- [ ] Scaffold background dùng `Theme.of(context).scaffoldBackgroundColor`
- [ ] Text dùng `Theme.of(context).textTheme.*`
- [ ] Card/Container dùng `Theme.of(context).cardColor`
- [ ] Icon dùng `Theme.of(context).iconTheme.color`
- [ ] Border dùng `Theme.of(context).dividerColor`
- [ ] KHÔNG hard-code `Colors.white`, `Colors.black`, `Colors.grey`
- [ ] Test trên cả Light và Dark mode

## 🔄 Auto-load

File `.kiro/steering/theme-system.md` sẽ tự động được load khi code.

Mọi màn hình mới sẽ được nhắc nhở tuân theo theme system.

## 📱 Demo

Để test theme:
1. Thêm `ThemeToggleButton()` vào AppBar của LoginScreen
2. Chạy app và click icon sun/moon
3. Theme sẽ chuyển đổi và lưu lại preference

---

**Status**: ✅ Ready to use
**Last Updated**: 2024
**Version**: 1.0.0
