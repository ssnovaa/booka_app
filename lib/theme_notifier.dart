// lib/theme_notifier.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _prefKeyMode = 'theme_mode_v2';
  static const _prefKeyDayStart = 'theme_auto_day_start';
  static const _prefKeyNightStart = 'theme_auto_night_start';

  String _modeName = 'auto';
  int _dayStartHour = 7;
  int _nightStartHour = 20;
  Timer? _autoTimer;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get modeName => _modeName;
  bool get isAuto => _modeName == 'auto';

  bool get isDark {
    switch (_modeName) {
      case 'dark':
        return true;
      case 'light':
        return false;
      case 'auto':
      default:
        return _isNightNow();
    }
  }

  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyMode);
    _modeName = switch (saved) {
      'light' => 'light',
      'dark' => 'dark',
      'system' => 'auto',
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
    if (!['light', 'dark', 'auto'].contains(name)) name = 'auto';
    _modeName = name;
    _rearmAutoTimer();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyMode, _modeName);
  }

  Future<void> setMode(ThemeMode mode) =>
      setModeName(mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'auto');

  Future<void> toggleTheme() => toggleDarkLight();

  Future<void> toggleDarkLight() => setModeName(_modeName == 'dark' ? 'light' : 'dark');

  Future<void> cycleMode() async {
    switch (_modeName) {
      case 'light':
        await setModeName('dark');
        break;
      case 'dark':
        await setModeName('auto');
        break;
      case 'auto':
      default:
        await setModeName('light');
        break;
    }
  }

  Future<void> setAutoSchedule({int? dayStartHour, int? nightStartHour}) async {
    if (dayStartHour != null) _dayStartHour = dayStartHour.clamp(0, 23).toInt();
    if (nightStartHour != null) _nightStartHour = nightStartHour.clamp(0, 23).toInt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyDayStart, _dayStartHour);
    await prefs.setInt(_prefKeyNightStart, _nightStartHour);
    _rearmAutoTimer();
    notifyListeners();
  }

  bool _isNightNow() {
    final h = DateTime.now().hour;
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
      notifyListeners();
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
