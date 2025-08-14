// lib/user_notifier.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/models/user.dart';

class UserNotifier extends ChangeNotifier {
  User? _user;
  bool _isAuth = false;
  String? _token;

  User? get user => _user;
  bool get isAuth => _isAuth;
  bool get isGuest => !_isAuth;
  String? get token => _token;

  /// Попытка автоматически залогиниться (если в SharedPreferences есть token)
  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('token');
    if (stored == null || stored.isEmpty) {
      _isAuth = false;
      _user = null;
      _token = null;
      notifyListeners();
      return;
    }
    _token = stored;
    await fetchCurrentUser();
  }

  Future<void> checkAuth() async => tryAutoLogin();

  /// Логин по email/password — возвращает понятное сообщение в AppNetworkException при ошибке
  Future<void> loginWithEmail(String email, String password) async {
    try {
      final r = await ApiClient.i().post('/login', data: {'email': email, 'password': password});
      if (r.statusCode == 200) {
        final token = r.data['token'] as String?;
        final userJson = r.data['user'] as Map<String, dynamic>?;
        if (token != null && userJson != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          _token = token;
          _user = User.fromJson(userJson);
          _isAuth = true;
          notifyListeners();
          return;
        }
      }

      // Попытка извлечь читаемое сообщение из тела ответа
      String serverMsg = 'Ошибка входа (код ${r.statusCode})';
      try {
        final maybe = r.data;
        if (maybe is Map && (maybe['message'] != null || maybe['error'] != null)) {
          serverMsg = (maybe['message'] ?? maybe['error']).toString();
        } else if (maybe is String && maybe.isNotEmpty) {
          serverMsg = maybe;
        }
      } catch (_) {
        // ignore parsing errors
      }

      throw AppNetworkException(serverMsg, statusCode: r.statusCode);
    } on DioException catch (e) {
      // Попытка разобрать тело ошибки из DioException
      String msg = e.message ?? 'Сетевая ошибка';
      try {
        final data = e.response?.data;
        if (data != null) {
          if (data is Map && (data['message'] != null || data['error'] != null)) {
            msg = (data['message'] ?? data['error']).toString();
          } else {
            msg = data.toString();
          }
        }
      } catch (_) {
        // ignore parsing errors
      }

      if (e.response?.statusCode == 401) {
        msg = 'Неверный email или пароль';
      }

      throw AppNetworkException(msg, statusCode: e.response?.statusCode);
    } catch (e) {
      throw AppNetworkException('Ошибка: ${e.toString()}');
    }
  }

  Future<void> fetchCurrentUser() async {
    if (_token == null) {
      _isAuth = false;
      _user = null;
      notifyListeners();
      return;
    }

    try {
      final r = await ApiClient.i().get('/me');
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        _user = User.fromJson(r.data as Map<String, dynamic>);
        _isAuth = true;
      } else {
        await _clearAuth();
      }
    } on DioException {
      await _clearAuth();
    }
    notifyListeners();
  }

  /// Переключиться в гостевой режим: очистить токен/профиль, но не выполнять навигацию.
  /// Это полезно, когда пользователь нажимает "Продолжить как гость".
  Future<void> continueAsGuest() async {
    await _clearAuth();
    // _clearAuth не вызывает notifyListeners(), поэтому делаем это здесь
    notifyListeners();
  }

  Future<void> logout() async {
    await _clearAuth();
    notifyListeners();
  }

  Future<void> _clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _user = null;
    _isAuth = false;
    _token = null;
  }
}
