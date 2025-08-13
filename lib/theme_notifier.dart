import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _themePrefKey = 'isDarkTheme';
  bool _isDark = false;

  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  ThemeNotifier() {
    // При создании Notifier'а загружаем сохраненную тему
    _loadThemeFromPrefs();
  }

  // Переключает тему на противоположную
  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    await _saveThemeToPrefs();
    notifyListeners();
  }

  // Устанавливает конкретную тему
  Future<void> setTheme(bool isDark) async {
    _isDark = isDark;
    await _saveThemeToPrefs();
    notifyListeners();
  }

  // Внутренний метод для загрузки темы из памяти устройства
  Future<void> _loadThemeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Загружаем значение, по умолчанию - false (светлая тема)
    _isDark = prefs.getBool(_themePrefKey) ?? false;
    notifyListeners();
  }

  // Внутренний метод для сохранения темы в память устройства
  Future<void> _saveThemeToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themePrefKey, _isDark);
  }
}
