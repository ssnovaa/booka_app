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
  String? get token => _token;

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
      throw AppNetworkException('Login failed', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
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
