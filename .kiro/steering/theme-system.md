---
inclusion: auto
---

# VinExpress - Hệ Thống Theme Sáng/Tối

## 🌓 Yêu cầu Bắt buộc

**TẤT CẢ các màn hình/trang mới phải hỗ trợ theme sáng và tối.**

## 📋 Quy tắc Thiết kế Theme

### 1. KHÔNG Hard-code Màu
```dart
// ❌ SAI - Hard-code màu
Container(
  color: Colors.white,
  child: Text('Hello', style: TextStyle(color: Colors.black)),
)

// ✅ ĐÚNG - Dùng Theme
Container(
  color: Theme.of(context).scaffoldBackgroundColor,
  child: Text(
    'Hello',
    style: Theme.of(context).textTheme.bodyLarge,
  ),
)
```

### 2. Sử dụng Theme Context
```dart
// Màu background
Theme.of(context).scaffoldBackgroundColor
Theme.of(context).cardColor

// Màu text
Theme.of(context).textTheme.bodyLarge
Theme.of(context).textTheme.titleLarge
Theme.of(context).colorScheme.onBackground

// Màu primary/secondary
Theme.of(context).colorScheme.primary
Theme.of(context).colorScheme.secondary

// Màu surface
Theme.of(context).colorScheme.surface
Theme.of(context).colorScheme.onSurface
```

### 3. AppColors - Theme Aware
Sử dụng `AppColors` với context:
```dart
// Dynamic colors dựa trên theme
AppColors.getBackground(context)
AppColors.getTextPrimary(context)
AppColors.getSurface(context)
```

## 🎨 Bảng Màu Theme

### Light Theme (Sáng)
- **Background**: `#FFFFFF` (Trắng)
- **Surface**: `#FAFAFA` (Xám nhạt)
- **Text Primary**: `#212121` (Đen xám)
- **Text Secondary**: `#757575` (Xám)
- **Primary**: `#00BFA5` (Teal)
- **Secondary**: `#26C6DA` (Cyan)

### Dark Theme (Tối)
- **Background**: `#121212` (Đen xám đậm)
- **Surface**: `#1E1E1E` (Xám đen)
- **Text Primary**: `#FFFFFF` (Trắng)
- **Text Secondary**: `#B0B0B0` (Xám nhạt)
- **Primary**: `#00BFA5` (Teal - giữ nguyên)
- **Secondary**: `#26C6DA` (Cyan - giữ nguyên)

## 🔧 Cấu trúc Theme

### ThemeProvider (Provider Pattern)
```dart
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light 
        ? ThemeMode.dark 
        : ThemeMode.light;
    notifyListeners();
  }
  
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}
```

### App Setup
```dart
MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: themeProvider.themeMode,
  home: LoginScreen(),
)
```

## 📱 Component Guidelines

### Scaffold
```dart
Scaffold(
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  appBar: AppBar(
    backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
  ),
)
```

### Card/Container
```dart
Container(
  decoration: BoxDecoration(
    color: Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Theme.of(context).shadowColor,
        blurRadius: 8,
      ),
    ],
  ),
)
```

### Text
```dart
// Heading
Text(
  'Title',
  style: Theme.of(context).textTheme.titleLarge?.copyWith(
    fontWeight: FontWeight.bold,
  ),
)

// Body
Text(
  'Content',
  style: Theme.of(context).textTheme.bodyMedium,
)

// Caption
Text(
  'Hint',
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
  ),
)
```

### Input Fields
```dart
TextFormField(
  decoration: InputDecoration(
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface,
    labelStyle: TextStyle(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
    ),
    border: OutlineInputBorder(
      borderSide: BorderSide(
        color: Theme.of(context).dividerColor,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 2,
      ),
    ),
  ),
)
```

### Buttons
```dart
// Primary button với gradient (vẫn giữ màu brand)
Container(
  decoration: BoxDecoration(
    gradient: AppColors.primaryGradient,
    borderRadius: BorderRadius.circular(12),
  ),
  child: ElevatedButton(...),
)

// Secondary button (theo theme)
OutlinedButton(
  style: OutlinedButton.styleFrom(
    foregroundColor: Theme.of(context).colorScheme.primary,
    side: BorderSide(
      color: Theme.of(context).colorScheme.primary,
    ),
  ),
  child: Text('Button'),
)
```

### Icons
```dart
Icon(
  Icons.settings,
  color: Theme.of(context).iconTheme.color,
)
```

## 🎯 Checklist Khi Tạo Màn Hình Mới

- [ ] Scaffold background dùng `Theme.of(context).scaffoldBackgroundColor`
- [ ] Text dùng `Theme.of(context).textTheme.*`
- [ ] Card/Surface dùng `Theme.of(context).cardColor`
- [ ] Icon dùng `Theme.of(context).iconTheme.color`
- [ ] Border/Divider dùng `Theme.of(context).dividerColor`
- [ ] Shadow dùng `Theme.of(context).shadowColor`
- [ ] KHÔNG hard-code `Colors.white`, `Colors.black`, `Colors.grey`
- [ ] Kiểm tra hiển thị trên cả Light và Dark mode

## ⚠️ Ngoại lệ

Chỉ những màu sau được phép hard-code:
1. **Brand Colors**: `AppColors.primary`, `AppColors.secondary` (luôn giữ nguyên)
2. **Status Colors**: Success (xanh lá), Error (đỏ), Warning (cam)
3. **Gradient**: `AppColors.primaryGradient` (brand identity)

## 🔄 Toggle Theme

### Settings Screen
```dart
SwitchListTile(
  title: Text('Giao diện tối'),
  value: themeProvider.isDarkMode,
  onChanged: (value) {
    themeProvider.toggleTheme();
  },
)
```

### Dropdown
```dart
DropdownButton<ThemeMode>(
  value: themeProvider.themeMode,
  items: [
    DropdownMenuItem(value: ThemeMode.system, child: Text('Theo hệ thống')),
    DropdownMenuItem(value: ThemeMode.light, child: Text('Sáng')),
    DropdownMenuItem(value: ThemeMode.dark, child: Text('Tối')),
  ],
  onChanged: (mode) {
    themeProvider.setThemeMode(mode!);
  },
)
```

## 📂 File Structure

```
lib/
├── core/
│   ├── constants/
│   │   └── app_colors.dart       # Brand colors
│   ├── theme/
│   │   ├── app_theme.dart        # Theme definitions
│   │   └── theme_provider.dart   # Theme state management
```

## 🎨 Màu Đặc biệt trong Dark Mode

```dart
// Dark mode cần màu surface nổi bật hơn background một chút
Color surface = isDarkMode 
    ? Color(0xFF1E1E1E)  // #1E1E1E
    : Color(0xFFFAFAFA); // #FAFAFA

// Divider trong dark mode cần sáng hơn
Color divider = isDarkMode
    ? Color(0xFF2C2C2C)
    : Color(0xFFE0E0E0);
```

## 📝 Ví dụ Màn hình Hoàn chỉnh

```dart
class ExampleScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Example',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Theme.of(context).cardColor,
              child: ListTile(
                title: Text(
                  'Title',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  'Subtitle',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Icon(
                  Icons.arrow_forward,
                  color: Theme.of(context).iconTheme.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

**LƯU Ý**: File này được auto-include. Mọi code mới phải tuân thủ các quy tắc trên.

**Ngày tạo**: 2024
**Phiên bản**: 1.0.0
