import 'package:flutter/material.dart';
import 'booka_app_bar_title.dart';
import 'theme_toggle_action.dart';

/// Единый AppBar приложения.
/// Добавляет заголовок и ГЛОБАЛЬНУЮ кнопку переключения темы в конец actions.
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
      ...actions,               // твои кнопки (настройки и т.п.)
      const ThemeToggleAction() // глобальная кнопка темы — всегда есть
    ],
    bottom: bottom,
  );
}
