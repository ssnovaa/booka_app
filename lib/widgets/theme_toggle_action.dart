// lib/widgets/theme_toggle_action.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_notifier.dart';

/// Іконка-перемикач теми: Light → Dark → Auto → ...
class ThemeToggleAction extends StatelessWidget {
  const ThemeToggleAction({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeNotifier>();

    // Іконки: light ☀️, dark 🌙, auto 🅰️
    final icon = switch (theme.modeName) {
      'light' => Icons.light_mode,
      'dark'  => Icons.dark_mode,
      'auto'  => Icons.brightness_auto,
      _       => Icons.light_mode,
    };

    final label = switch (theme.modeName) {
      'light' => 'Світла тема',
      'dark'  => 'Темна тема',
      'auto'  => 'Авто за часом',
      _       => 'Тема',
    };

    return IconButton(
      tooltip: label,
      icon: Icon(icon),
      onPressed: () => theme.cycleMode(), // Light → Dark → Auto → ...
    );
  }
}
