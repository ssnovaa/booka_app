// ПУТЬ: lib/theme_notifier.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3 режима: Light / Dark / Auto(по времени суток 07:00–20:00).
/// Без System. Если в сохранённом состоянии был 'system', мигрируем в 'auto'.
class ThemeNotifier extends ChangeNotifier {
  static const _prefKeyMode = 'theme_mode_v2'; // 'light' | 'dark' | 'auto'
  static const _prefKeyDayStart = 'theme_auto_day_start';   // по умолчанию 7
  static const _prefKeyNightStart = 'theme_auto_night_start'; // по умолчанию 20

  String _modeName = 'auto'; // авто по умолчанию
  int _dayStartHour = 7;
  int _nightStartHour = 20;
  Timer? _autoTimer;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get modeName => _modeName;
  bool get isAuto => _modeName == 'auto';

  /// Тёмно ли сейчас? В auto — по времени; в остальных — по режиму.
  bool get isDark {
    switch (_modeName) {
      case 'dark': return true;
      case 'light': return false;
      case 'auto':
      default: return _isNightNow();
    }
  }

  /// То, что подаём в MaterialApp.themeMode.
  /// В auto возвращаем light/dark динамически.
  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyMode);
    // миграция: старый 'system' -> 'auto'
    _modeName = switch (saved) {
      'light' => 'light',
      'dark' => 'dark',
      'system' => 'auto', // мигрируем
      'auto' => 'auto',
      _ => 'auto',
    };
    _dayStartHour = prefs.getInt(_prefKeyDayStart) ?? 7;
    _nightStartHour = prefs.getInt(_prefKeyNightStart) ?? 20;
    _loaded = true;
    _rearmAutoTimer();
    notifyListeners();
  }

  Future<void> setModeName(String name) async {
    if (!['light','dark','auto'].contains(name)) name = 'auto';
    _modeName = name;
    _rearmAutoTimer();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyMode, _modeName);
  }

  /// Сохранение через ThemeMode: system трактуем как auto (для совместимости).
  Future<void> setMode(ThemeMode mode) =>
      setModeName(mode == ThemeMode.dark ? 'dark'
          : mode == ThemeMode.light ? 'light'
          : 'auto'); // system -> auto

  /// Совместимость со старым кодом.
  Future<void> toggleTheme() => toggleDarkLight();

  /// Быстрое Light↔Dark.
  Future<void> toggleDarkLight() => setModeName(_modeName == 'dark' ? 'light' : 'dark');

  /// Цикл: Light → Dark → Auto → Light…
  Future<void> cycleMode() async {
    switch (_modeName) {
      case 'light': await setModeName('dark'); break;
      case 'dark': await setModeName('auto'); break;
      case 'auto':
      default: await setModeName('light'); break;
    }
  }

  /// Настройка часов авто-режима (например, 6 и 21).
  Future<void> setAutoSchedule({int? dayStartHour, int? nightStartHour}) async {
    if (dayStartHour != null) _dayStartHour = dayStartHour.clamp(0, 23);
    if (nightStartHour != null) _nightStartHour = nightStartHour.clamp(0, 23);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyDayStart, _dayStartHour);
    await prefs.setInt(_prefKeyNightStart, _nightStartHour);
    _rearmAutoTimer();
    notifyListeners();
  }

  // ---------- внутреннее ----------
  bool _isNightNow() {
    final h = DateTime.now().hour;
    // Ночь — [nightStart..24) ∪ [0..dayStart)
    return (h >= _nightStartHour) || (h < _dayStartHour);
  }

  void _rearmAutoTimer() {
    _autoTimer?.cancel();
    if (_modeName != 'auto') return;

    final now = DateTime.now();
    final nextDay = _nextOccurrence(now, _dayStartHour);
    final nextNight = _nextOccurrence(now, _nightStartHour);
    final next = nextDay.isBefore(nextNight) ? nextDay : nextNight;
    _autoTimer = Timer(next.difference(now), () {
      notifyListeners(); // перерисуем тему (light/dark)
      _rearmAutoTimer();
    });
  }

  DateTime _nextOccurrence(DateTime from, int hour) {
    var t = DateTime(from.year, from.month, from.day, hour);
    if (!t.isAfter(from)) t = t.add(const Duration(days: 1));
    return t;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }
}
