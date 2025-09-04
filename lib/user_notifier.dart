// lib/user_notifier.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

import 'package:booka_app/models/user.dart';
import 'package:booka_app/repositories/profile_repository.dart';

class UserNotifier extends ChangeNotifier {
  User? _user;
  bool _isAuth = false;

  User? get user => _user;
  bool get isAuth => _isAuth;
  bool get isGuest => !_isAuth;

  String? get token => AuthStore.I.accessToken;

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

  Future<void> loginWithEmail(String email, String password) async {
    try {
      Response r;

      try {
        r = await ApiClient.i().post('/auth/login', data: {
          'email': email,
          'password': password,
        });
      } on DioException catch (e) {
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

        final Map<String, dynamic>? userJson = (data is Map)
            ? (data['user'] ?? data['profile']) as Map<String, dynamic>?
            : null;

        if (access != null && access.isNotEmpty) {
          await AuthStore.I.save(
            access: access,
            refresh: refresh,
            accessExp: accessExp,
          );

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
      final sc = e.response?.statusCode ?? 0;
      if (sc == 401 || sc == 403) {
        await _clearAuth();
      } else {
        rethrow;
      }
    } catch (_) {
      await _clearAuth();
    }
    notifyListeners();
  }

  Future<void> continueAsGuest() async {
    await _clearAuth();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      final refresh = AuthStore.I.refreshToken;
      await ApiClient.i().post(
        '/auth/logout',
        data: {if (refresh != null) 'refresh_token': refresh},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
    } catch (_) {
    } finally {
      await _clearAuth();
      notifyListeners();
    }
  }

  Future<void> _clearAuth() async {
    await AuthStore.I.clear();
    _user = null;
    _isAuth = false;
    try {
      ProfileRepository.I.invalidate();
    } catch (_) {}
  }
}
