import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider quản lý theme mode (Light/Dark/System)
class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeProvider() {
    _loadThemeMode();
  }
  
  /// Get current theme mode
  ThemeMode get themeMode => _themeMode;
  
  /// Check if current theme is dark
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
  /// Check if current theme is light
  bool get isLightMode => _themeMode == ThemeMode.light;
  
  /// Check if current theme is system
  bool get isSystemMode => _themeMode == ThemeMode.system;
  
  /// Toggle between light and dark mode
  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
  
  /// Set specific theme mode
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveThemeMode(mode);
    notifyListeners();
  }
  
  /// Load theme mode from SharedPreferences
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_themeModeKey);
      
      if (themeModeString != null) {
        _themeMode = _parseThemeMode(themeModeString);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading theme mode: $e');
    }
  }
  
  /// Save theme mode to SharedPreferences
  Future<void> _saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.toString());
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }
  
  /// Parse ThemeMode from string
  ThemeMode _parseThemeMode(String modeString) {
    switch (modeString) {
      case 'ThemeMode.light':
        return ThemeMode.light;
      case 'ThemeMode.dark':
        return ThemeMode.dark;
      case 'ThemeMode.system':
      default:
        return ThemeMode.system;
    }
  }
  
  /// Get theme mode display name
  String getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Sáng';
      case ThemeMode.dark:
        return 'Tối';
      case ThemeMode.system:
        return 'Theo hệ thống';
    }
  }
  
  /// Get current theme mode display name
  String get currentThemeModeName => getThemeModeName(_themeMode);
}
