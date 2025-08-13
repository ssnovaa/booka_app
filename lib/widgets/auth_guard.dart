import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/login_screen.dart';

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
    checkAuth();
  }

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    setState(() {
      isAuth = token != null && token.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isAuth == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!isAuth!) {
      // Не авторизован — показываем экран логина
      return const LoginScreen();
    }
    // Авторизован — показываем защищённый экран
    return widget.child;
  }
}
