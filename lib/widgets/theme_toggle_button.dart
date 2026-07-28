import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/theme_provider.dart';

/// Widget để toggle theme giữa sáng và tối
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return IconButton(
      icon: Icon(
        themeProvider.isDarkMode 
            ? Icons.light_mode_outlined 
            : Icons.dark_mode_outlined,
      ),
      onPressed: () {
        themeProvider.toggleTheme();
      },
      tooltip: themeProvider.isDarkMode 
          ? 'Chuyển sang giao diện sáng' 
          : 'Chuyển sang giao diện tối',
    );
  }
}

/// Widget switch để bật/tắt dark mode trong settings
class ThemeToggleSwitch extends StatelessWidget {
  const ThemeToggleSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return SwitchListTile(
      title: Text(
        'Giao diện tối',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        'Bật chế độ giao diện tối',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: themeProvider.isDarkMode,
      onChanged: (value) {
        if (value) {
          themeProvider.setThemeMode(ThemeMode.dark);
        } else {
          themeProvider.setThemeMode(ThemeMode.light);
        }
      },
      activeThumbColor: Theme.of(context).colorScheme.primary,
      secondary: Icon(
        themeProvider.isDarkMode 
            ? Icons.dark_mode 
            : Icons.light_mode,
        color: Theme.of(context).iconTheme.color,
      ),
    );
  }
}

/// Widget để chọn theme mode (System/Light/Dark)
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Chủ đề',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Theo hệ thống'),
          subtitle: const Text('Tự động theo cài đặt thiết bị'),
          value: ThemeMode.system,
          groupValue: themeProvider.themeMode,
          onChanged: (value) {
            if (value != null) {
              themeProvider.setThemeMode(value);
            }
          },
          activeColor: Theme.of(context).colorScheme.primary,
          secondary: const Icon(Icons.brightness_auto),
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Sáng'),
          subtitle: const Text('Luôn dùng giao diện sáng'),
          value: ThemeMode.light,
          groupValue: themeProvider.themeMode,
          onChanged: (value) {
            if (value != null) {
              themeProvider.setThemeMode(value);
            }
          },
          activeColor: Theme.of(context).colorScheme.primary,
          secondary: const Icon(Icons.light_mode),
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Tối'),
          subtitle: const Text('Luôn dùng giao diện tối'),
          value: ThemeMode.dark,
          groupValue: themeProvider.themeMode,
          onChanged: (value) {
            if (value != null) {
              themeProvider.setThemeMode(value);
            }
          },
          activeColor: Theme.of(context).colorScheme.primary,
          secondary: const Icon(Icons.dark_mode),
        ),
      ],
    );
  }
}
