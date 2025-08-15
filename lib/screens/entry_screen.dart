// lib/screens/entry_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../user_notifier.dart';
import 'main_screen.dart';

import '../core/network/api_client.dart';
import '../core/network/auth_interceptor.dart';
import '../core/network/auth/auth_store.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({Key? key}) : super(key: key);

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _isLoading = true;
  bool _interceptorAttached = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // 1) инициализируем Dio/кэш
      await ApiClient.init();

      // 2) восстанавливаем токены
      await AuthStore.I.restore();

      // 3) подключаем AuthInterceptor (ровно один раз)
      final dio = ApiClient.i();
      if (!_interceptorAttached) {
        dio.interceptors.removeWhere((it) => it is AuthInterceptor);
        dio.interceptors.add(AuthInterceptor(
          refreshPath: '/auth/refresh',
          headerPrefix: 'Bearer ',
        ));
        _interceptorAttached = true;
      }

      // 4) проверяем авторизацию
      final userNotifier = Provider.of<UserNotifier>(context, listen: false);
      await userNotifier.checkAuth();
    } catch (_) {
      // гостевой режим — ок
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const MainScreen();
  }
}
