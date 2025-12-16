// lib/widgets/booka_app_bar.dart
import 'package:flutter/material.dart';
import 'booka_app_bar_title.dart';
import 'theme_toggle_action.dart';
import 'ad_timer_badge.dart'; // 1. Импорт должен быть здесь

PreferredSizeWidget bookaAppBar({
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
  Color? backgroundColor,
  bool centerTitle = false,
}) {
  return AppBar(
    backgroundColor: backgroundColor,
    elevation: 0,
    centerTitle: centerTitle,
    title: const BookaAppBarTitle(),
    actions: [
      ...actions,

      // 2. Таймер должен быть здесь
      const AdTimerBadge(),

      const ThemeToggleAction(),
    ],
    bottom: bottom,
  );
}