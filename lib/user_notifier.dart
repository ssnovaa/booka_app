// lib/user_notifier.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/core/network/auth/auth_store.dart'; // ← корректный путь

import 'package:booka_app/models/user.dart';

// новый единый источник профиля (single-flight + короткий TTL)
import 'package:booka_app/repositories/profile_repository.dart';

class UserNotifier extends ChangeNotifier {
  User? _user;
  bool _isAuth = false;

  User? get user => _user;
  bool get isAuth => _isAuth;
  bool get isGuest => !_isAuth;

  /// Если кому-то нужен access-токен из стора (лучше не дергать напрямую).
  String? get token => AuthStore.I.accessToken;

  /// Проверка авторизации при старте приложения.
  /// Предполагается, что EntryScreen уже вызвал AuthStore.I.restore()
  Future<void> tryAutoLogin() async {
    if (!AuthStore.I.isLoggedIn) {
      _isAuth = false;
      _user = null;
      notifyListeners();
      return;
    }
    await fetchCurrentUser();
  }

  Future<void> checkAuth() async => tryAutoLogin();

  /// Логин по email/password.
  /// Поддерживает оба варианта бэкенда:
  /// 1) Новый:  POST /auth/login → { access_token, access_expires_at, refresh_token, user|profile }
  /// 2) Старый: POST /login      → { token, user? }  (без refresh — живём без рефреша)
  Future<void> loginWithEmail(String email, String password) async {
    try {
      Response r;

      // Пытаемся новый эндпоинт
      try {
        r = await ApiClient.i().post('/auth/login', data: {
          'email': email,
          'password': password,
        });
      } on DioException catch (e) {
        // Если /auth/login отсутствует — fallback на старый /login
        final code = e.response?.statusCode ?? 0;
        if (code == 404 || code == 405) {
          r = await ApiClient.i().post('/login', data: {
            'email': email,
            'password': password,
          });
        } else {
          rethrow;
        }
      }

      if (r.statusCode == 200) {
        final data = r.data;

        // Токены (новый/старый форматы)
        final String? access = (data is Map)
            ? (data['access_token'] ?? data['token']) as String?
            : null;

        final String? refresh = (data is Map)
            ? (data['refresh_token'] as String?)
            : null;

        final String? accessExpStr =
        (data is Map) ? (data['access_expires_at'] as String?) : null;
        final DateTime? accessExp =
        (accessExpStr != null) ? DateTime.tryParse(accessExpStr) : null;

        // Пользователь (user | profile)
        final Map<String, dynamic>? userJson = (data is Map)
            ? (data['user'] ?? data['profile']) as Map<String, dynamic>?
            : null;

        if (access != null && access.isNotEmpty) {
          await AuthStore.I.save(
            access: access,
            refresh: refresh, // может быть null — тогда живём без рефреша
            accessExp: accessExp,
          );

          // Если сервер сразу не отдал профиль — тянем через репозиторий
          if (userJson != null) {
            _user = User.fromJson(userJson);
          } else {
            _user = await ProfileRepository.I.load();
          }

          _isAuth = true;
          notifyListeners();
          return;
        }
      }

      // Если дошли сюда — считаем, что это ошибка логина с сообщением сервера (если есть)
      String serverMsg = 'Помилка входу (код ${r.statusCode})';
      try {
        final body = r.data;
        if (body is Map && (body['message'] != null || body['error'] != null)) {
          serverMsg = (body['message'] ?? body['error']).toString();
        } else if (body is String && body.isNotEmpty) {
          serverMsg = body;
        }
      } catch (_) {}
      throw AppNetworkException(serverMsg, statusCode: r.statusCode);
    } on DioException catch (e) {
      // Читаем сообщение ошибки из тела, если есть
      String msg = e.message ?? 'Мережева помилка';
      try {
        final data = e.response?.data;
        if (data != null) {
          if (data is Map && (data['message'] != null || data['error'] != null)) {
            msg = (data['message'] ?? data['error']).toString();
          } else if (data is String && data.isNotEmpty) {
            msg = data;
          }
        }
      } catch (_) {}
      if (e.response?.statusCode == 401) {
        msg = 'Невірний email або пароль';
      }
      throw AppNetworkException(msg, statusCode: e.response?.statusCode);
    } catch (e) {
      throw AppNetworkException('Помилка: $e');
    }
  }

  /// Получение текущего пользователя через единый репозиторий.
  Future<void> fetchCurrentUser() async {
    if (!AuthStore.I.isLoggedIn) {
      await _clearAuth();
      notifyListeners();
      return;
    }

    try {
      final u = await ProfileRepository.I.load();
      _user = u;
      _isAuth = true;
    } on DioException catch (e) {
      // Неавторизован — чистим стейт
      final sc = e.response?.statusCode ?? 0;
      if (sc == 401 || sc == 403) {
        await _clearAuth();
      } else {
        // другие сетевые сбои: не рушим авторизацию, но можно пробросить при желании
        rethrow;
      }
    } catch (_) {
      // Любая иная ошибка — считаем неавторизованным
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
    try {
      final refresh = AuthStore.I.refreshToken;
      // Если новый API есть — корректно выходим
      await ApiClient.i().post(
        '/auth/logout',
        data: { if (refresh != null) 'refresh_token': refresh },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
    } catch (_) {
      // старый бекенд без /auth/logout — просто игнорируем
    } finally {
      await _clearAuth();
      notifyListeners();
    }
  }

  // ================== helpers ==================

  Future<void> _clearAuth() async {
    await AuthStore.I.clear();
    _user = null;
    _isAuth = false;
    // сбросим кэш профиля, чтобы после релогина не подтянулся старый
    try {
      ProfileRepository.I.invalidate();
    } catch (_) {}
  }
}
