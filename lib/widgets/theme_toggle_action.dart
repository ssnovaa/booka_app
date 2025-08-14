import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_notifier.dart';

/// Иконка-переключатель темы: Light → Dark → System → Auto → ...
class ThemeToggleAction extends StatelessWidget {
  const ThemeToggleAction({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeNotifier>();
    final icon = switch (theme.modeName) {
      'light' => Icons.light_mode,
      'dark' => Icons.dark_mode,
      'system' => Icons.brightness_auto,
      'auto' => Icons.schedule,
      _ => Icons.brightness_auto,
    };
    final label = switch (theme.modeName) {
      'light' => 'Світла тема',
      'dark' => 'Темна тема',
      'system' => 'Системна тема',
      'auto' => 'Авто за часом',
      _ => 'Тема',
    };

    return IconButton(
      tooltip: label,
      icon: Icon(icon),
      onPressed: () => theme.cycleMode(),
    );
  }
}
