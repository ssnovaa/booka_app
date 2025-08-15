// lib/user_notifier.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

import 'package:booka_app/models/user.dart';

class UserNotifier extends ChangeNotifier {
  User? _user;
  bool _isAuth = false;

  User? get user => _user;
  bool get isAuth => _isAuth;
  bool get isGuest => !_isAuth;

  /// Если кому-то нужен access-токен из стора (не рекомендуется дергать напрямую)
  String? get token => AuthStore.I.accessToken;

  /// Проверка авторизации при старте приложения.
  /// Предполагается, что EntryScreen уже вызвал AuthStore.I.restore()
  Future<void> tryAutoLogin() async {
    if (!AuthStore.I.hasTokens) {
      _isAuth = false;
      _user = null;
      notifyListeners();
      return;
    }
    await fetchCurrentUser();
  }

  Future<void> checkAuth() async => tryAutoLogin();

  /// Логин по email/password.
  /// Поддерживает оба варианта ответа бэкенда:
  /// 1) { token, user }
  /// 2) { access_token, refresh_token, user | profile }
  Future<void> loginWithEmail(String email, String password) async {
    try {
      final r = await ApiClient.i().post('/login', data: {
        'email': email,
        'password': password,
      });

      if (r.statusCode == 200) {
        final data = r.data;

        // Токены
        final String? access =
        (data is Map) ? (data['access_token'] ?? data['token']) as String? : null;
        final String? refresh =
        (data is Map) ? (data['refresh_token'] ?? data['token']) as String? : null;

        // Пользователь
        final Map<String, dynamic>? userJson = (data is Map)
            ? (data['user'] ?? data['profile']) as Map<String, dynamic>?
            : null;

        if (access != null && refresh != null && userJson != null) {
          await AuthStore.I.saveTokens(
            accessToken: access,
            refreshToken: refresh,
          );
          _user = User.fromJson(userJson);
          _isAuth = true;
          notifyListeners();
          return;
        }
      }

      // Попытка извлечь читаемое сообщение из тела ответа
      String serverMsg = 'Помилка входу (код ${r.statusCode})';
      try {
        final maybe = r.data;
        if (maybe is Map && (maybe['message'] != null || maybe['error'] != null)) {
          serverMsg = (maybe['message'] ?? maybe['error']).toString();
        } else if (maybe is String && maybe.isNotEmpty) {
          serverMsg = maybe;
        }
      } catch (_) {
        // ignore
      }

      throw AppNetworkException(serverMsg, statusCode: r.statusCode);
    } on DioException catch (e) {
      // Читаем сообщение ошибки из тела, если есть
      String msg = e.message ?? 'Мережева помилка';
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
        // ignore
      }

      if (e.response?.statusCode == 401) {
        msg = 'Невірний email або пароль';
      }

      throw AppNetworkException(msg, statusCode: e.response?.statusCode);
    } catch (e) {
      throw AppNetworkException('Помилка: $e');
    }
  }

  /// Получение текущего пользователя.
  /// Сначала пробуем /profile, если 404 — пробуем /me.
  Future<void> fetchCurrentUser() async {
    if (!AuthStore.I.hasTokens) {
      _isAuth = false;
      _user = null;
      notifyListeners();
      return;
    }

    Response r;

    try {
      r = await ApiClient.i().get(
        '/profile',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      // Если эндпоинта нет — fallback на /me
      if (r.statusCode == 404) {
        r = await ApiClient.i().get(
          '/me',
          options: Options(validateStatus: (s) => s != null && s < 500),
        );
      }

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

  /// Вход гостем — просто очищаем авторизацию.
  Future<void> continueAsGuest() async {
    await _clearAuth();
    notifyListeners();
  }

  /// Выход пользователя.
  Future<void> logout() async {
    // Если есть серверный /logout — можно дернуть его здесь try/catch
    // try { await ApiClient.i().post('/logout'); } catch (_) {}
    await _clearAuth();
    notifyListeners();
  }

  Future<void> _clearAuth() async {
    await AuthStore.I.clear();
    _user = null;
    _isAuth = false;
  }
}
