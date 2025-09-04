// lib/widgets/auth_guard.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:booka_app/widgets/loading_indicator.dart'; // ← Lottie-лоадер замість бублика
import 'package:booka_app/screens/login_screen.dart';

/// AuthGuard — простий охоронець маршрутів.
/// Поки не зрозуміло, чи є токен — показуємо Lottie-лоадер.
/// Якщо токена немає — віддаємо екран логіна.
/// Якщо токен є — показуємо дочірній контент [child].
class AuthGuard extends StatefulWidget {
  final Widget child;

  const AuthGuard({required this.child, super.key});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  bool? isAuth;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  /// Перевірка наявності токена у локальному сховищі.
  /// ⚠️ Зараз шукається ключ 'token', як у наявному коді.
  /// Якщо пізніше мігруєш на єдиний [AuthStore], тут варто звертатися до нього.
  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;
    setState(() {
      isAuth = token != null && token.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Стан ще не визначено — показуємо Lottie-індикатор.
    if (isAuth == null) {
      return const Center(child: LoadingIndicator());
    }

    // Неавторизований — ведемо на екран логіну.
    if (!isAuth!) {
      return const LoginScreen();
    }

    // Авторизований — показуємо вміст.
    return widget.child;
  }
}
