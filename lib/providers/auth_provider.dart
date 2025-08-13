import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class AuthProvider with ChangeNotifier {
  String? _authToken;
  bool _isLoading = false;

  String? get authToken => _authToken;
  bool get isAuthenticated => _authToken != null;
  bool get isLoading => _isLoading;

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Имитация запроса к API для входа
      await Future.delayed(const Duration(seconds: 1));
      // В реальном приложении здесь будет логика получения токена
      _authToken = 'mock-auth-token-12345';
    } catch (e) {
      print('Ошибка входа: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    _authToken = null;
    notifyListeners();
  }
}
