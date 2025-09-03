// lib/screens/entry_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// app
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // getUserType, UserType

// core
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth_interceptor.dart';
import 'package:booka_app/core/network/auth/auth_store.dart'; // <— единое хранилище токенов

class EntryScreen extends StatefulWidget {
  const EntryScreen({Key? key}) : super(key: key);

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _isLoading = true;
  bool _interceptorAttached = false;

  // Автосинхрон при возврате приложения из фона
  late final AppLifecycleListener _life;

  // Чтобы heavy-инициализация не запускалась повторно
  bool _didPostFrameHeavy = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onResume: () {
        final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
        final userN = Provider.of<UserNotifier>(context, listen: false);

        // Обновляем тип пользователя (вдруг тариф сменился) и подтягиваем прогресс с сервера
        audio.userType = getUserType(userN.user);
        audio.hydrateFromServerIfAvailable(); // безопасно: LWW-мердж внутри провайдера
      },
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final userNotifier = Provider.of<UserNotifier>(context, listen: false);
    final audio = Provider.of<AudioPlayerProvider>(context, listen: false);

    try {
      // 1) Сеть/кэш
      await ApiClient.init();

      // 2) Токены
      await AuthStore.I.restore();

      // 3) Авторизационный интерцептор (единая точка)
      final dio = ApiClient.i();
      if (!_interceptorAttached) {
        dio.interceptors.removeWhere((it) => it is AuthInterceptor);
        dio.interceptors.add(AuthInterceptor(dio)); // авто-refresh и ретрай
        _interceptorAttached = true;
      }

      // 4) Авторизация пользователя (авто-логин по сохранённым токенам)
      await userNotifier.tryAutoLogin();

      // 5) Тип пользователя для поведения плеера (читать только локальные данные)
      audio.userType = getUserType(userNotifier.user);

      // ⚠️ ТЯЖЁЛОЕ переносим после первого кадра (см. ниже),
      // чтобы не блокировать старт и уменьшить jank.
    } catch (_) {
      // остаёмся в гостевом режиме — ок
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);

      // Heavy-часть: после первого рендера экрана-заглушки.
      if (!_didPostFrameHeavy) {
        _didPostFrameHeavy = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Делаем «тяжёлое» уже после отрисовки первого кадра
          try {
            // 6) Прогрев плеера:
            //    - всегда восстановить локальное
            //    - ВСЕГДА попробовать подтянуть сервер (LWW-мердж внутри)
            //    - затем подготовить источник
            await audio.restoreProgress();
            await audio.hydrateFromServerIfAvailable();
            await audio.ensurePrepared();
          } catch (_) {
            // не критично для первого экрана
          }
        });
      }
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
