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
import 'package:booka_app/core/network/auth/auth_store.dart'; // <— єдине сховище токенів

class EntryScreen extends StatefulWidget {
  const EntryScreen({Key? key}) : super(key: key);

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _isLoading = true;
  bool _interceptorAttached = false;

  // Автосинхрон при поверненні застосунку з фону
  late final AppLifecycleListener _life;

  // Щоб heavy-ініціалізація не запускалася повторно
  bool _didPostFrameHeavy = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onResume: () {
        final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
        final userN = Provider.of<UserNotifier>(context, listen: false);

        // Оновлюємо тип користувача (раптом тариф змінився) і підтягуємо прогрес із сервера
        audio.userType = getUserType(userN.user);
        audio.hydrateFromServerIfAvailable(); // безпечно: LWW-мердж всередині провайдера
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
      // 1) Мережа/кеш
      await ApiClient.init();

      // 2) Токени
      await AuthStore.I.restore();

      // 3) Авторизаційний інтерцептор (єдина точка)
      final dio = ApiClient.i();
      if (!_interceptorAttached) {
        dio.interceptors.removeWhere((it) => it is AuthInterceptor);
        dio.interceptors.add(AuthInterceptor(dio)); // авто-refresh і ретрай
        _interceptorAttached = true;
      }

      // 4) Авторизація користувача (авто-логін за збереженими токенами)
      await userNotifier.tryAutoLogin();

      // 5) Тип користувача для поведінки плеєра (читати лише локальні дані)
      audio.userType = getUserType(userNotifier.user);

      // ⚠️ ВАЖКЕ переносимо після першого кадру (див. нижче),
      // щоб не блокувати старт і зменшити jank.
    } catch (_) {
      // залишаємося в гостьовому режимі — ок
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);

      // Heavy-частина: після першого рендера екрана-заглушки.
      if (!_didPostFrameHeavy) {
        _didPostFrameHeavy = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Робимо «важке» вже після відмалювання першого кадру
          try {
            // 6) Прогрів плеєра:
            //    - завжди відновити локальне
            //    - ЗАВЖДИ спробувати підвантажити сервер (LWW-мердж всередині)
            //    - потім підготувати джерело
            await audio.restoreProgress();
            await audio.hydrateFromServerIfAvailable();
            await audio.ensurePrepared();
          } catch (_) {
            // не критично для першого екрана
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
