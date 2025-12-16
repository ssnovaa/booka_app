// lib/widgets/booka_app_bar.dart
import 'package:flutter/material.dart';
import 'booka_app_bar_title.dart';
import 'theme_toggle_action.dart';
import 'ad_timer_badge.dart'; // 👈 Добавлен импорт

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
      // Сначала идут кнопки конкретной страницы (если есть)
      ...actions,

      // 👇 Таймер до рекламы (появляется только в Ad-Mode)
      const Center(
        child: Padding(
          padding: EdgeInsets.only(right: 8.0),
          child: AdTimerBadge(),
        ),
      ),

      // Переключатель темы (всегда справа)
      const ThemeToggleAction(),
    ],
    bottom: bottom,
  );
}