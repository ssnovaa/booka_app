import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/user.dart';
import 'constants.dart';

class UserNotifier extends ChangeNotifier {
  User? _user;
  bool _isAuth = false;
  String? _token;

  User? get user => _user;
  bool get isAuth => _isAuth;
  String? get token => _token;

  /// Попробовать авто-логин при старте приложения
  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('token');
    print('[UserNotifier] tryAutoLogin: storedToken=$storedToken');

    if (storedToken == null || storedToken.isEmpty) {
      print('[UserNotifier] tryAutoLogin: нет токена в prefs');
      _isAuth = false;
      _user = null;
      _token = null;
      notifyListeners();
      return;
    }
    _token = storedToken;
    print('[UserNotifier] tryAutoLogin: найден токен, пробуем fetchCurrentUser()');
    await fetchCurrentUser();
  }

  /// Логин (сохраняет токен и пользователя)
  Future<void> login(User user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    print('[UserNotifier] login: Сохранили токен=$token');
    _user = user;
    _isAuth = true;
    _token = token;
    notifyListeners();
  }

  /// Выход (удаляет токен и пользователя)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    print('[UserNotifier] logout: Удалили токен');
    _user = null;
    _isAuth = false;
    _token = null;
    notifyListeners();
  }

  /// Получить пользователя с сервера (и проверить токен)
  Future<void> fetchCurrentUser() async {
    print('[UserNotifier] fetchCurrentUser: _token=$_token');
    if (_token == null || _token!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      print('[UserNotifier] fetchCurrentUser: токен пустой, сбрасываем всё');
      _isAuth = false;
      _user = null;
      await prefs.remove('token');
      notifyListeners();
      return;
    }

    try {
      print('[UserNotifier] fetchCurrentUser: Делаем GET $BASE_URL/user');
      final response = await http.get(
        Uri.parse('$BASE_URL/profile'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      );
      print('[UserNotifier] fetchCurrentUser: status=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[UserNotifier] fetchCurrentUser: пользователь успешно получен');
        _user = User.fromJson(data);
        _isAuth = true;
      } else {
        print('[UserNotifier] fetchCurrentUser: невалидный токен/ошибка, очищаем всё');
        final prefs = await SharedPreferences.getInstance();
        _user = null;
        _isAuth = false;
        _token = null;
        await prefs.remove('token');
      }
      notifyListeners();
    } catch (e) {
      print('[UserNotifier] fetchCurrentUser: исключение $e');
      final prefs = await SharedPreferences.getInstance();
      _user = null;
      _isAuth = false;
      _token = null;
      await prefs.remove('token');
      notifyListeners();
    }
  }

  /// Используй это для ручной проверки статуса (если понадобится)
  Future<void> checkAuth() => tryAutoLogin();
}
