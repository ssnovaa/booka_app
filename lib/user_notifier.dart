import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/user.dart';
import 'constants.dart';

// Enum для четкого определения состояния аутентификации
enum AuthStatus { uninitialized, authenticating, authenticated, unauthenticated }

class UserNotifier extends ChangeNotifier {
  User? _user;
  AuthStatus _status = AuthStatus.uninitialized;
  String? _error;

  User? get user => _user;
  AuthStatus get status => _status;
  String? get error => _error;

  // Удобные геттеры для UI
  bool get isAuth => _status == AuthStatus.authenticated;
  bool get isAuthenticating => _status == AuthStatus.authenticating;
  UserType get userType => getUserType(_user);

  UserNotifier() {
    // Сразу при создании Notifier'а пытаемся выполнить автоматический вход
    tryAutoLogin();
  }

  /// Попробовать авто-логин при старте приложения
  Future<void> tryAutoLogin() async {
    _status = AuthStatus.authenticating;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null || token.isEmpty) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    // Если токен есть, проверяем его валидность, запрашивая данные пользователя
    await _fetchCurrentUser(token);
  }

  /// Логин по email и паролю
  Future<void> login(String email, String password) async {
    _status = AuthStatus.authenticating;
    _error = null;
    notifyListeners();

    try {
      final url = Uri.parse('$BASE_URL/login');
      final response = await http.post(url, body: {
        'email': email.trim(),
        'password': password.trim(),
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'] as String;
        final user = User.fromJson(data['user']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);

        _user = user;
        _status = AuthStatus.authenticated;
      } else {
        final data = json.decode(response.body);
        _error = data['message'] ?? 'Неверный логин или пароль';
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _error = 'Ошибка подключения. Проверьте интернет-соединение.';
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// Выход из системы
  Future<void> logout() async {
    _user = null;
    _status = AuthStatus.unauthenticated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    notifyListeners();
  }

  /// Внутренний метод для получения пользователя с сервера по токену
  Future<void> _fetchCurrentUser(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$BASE_URL/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _user = User.fromJson(data);
        _status = AuthStatus.authenticated;
      } else {
        // Если токен невалиден, выходим из системы
        await logout();
      }
    } catch (e) {
      await logout();
    }
    notifyListeners();
  }
}
