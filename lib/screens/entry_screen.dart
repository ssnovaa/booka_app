// lib/screens/entry_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode; // 👈 только для debug-кнопки
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

// app
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // getUserType, UserType
import 'package:booka_app/screens/reward_test_screen.dart'; // 👈 экран теста рекламы

// core
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth_interceptor.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

// ui
import 'package:booka_app/widgets/loading_indicator.dart'; // ← єдина точка Lottie-лоадера

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _isLoading = true;
  bool _interceptorAttached = false;

  late final AppLifecycleListener _life;
  bool _didPostFrameHeavy = false;

  @override
  void initState() {
    super.initState();

    // 🔁 На повернення у фокус — тримаємо просту локал-first стратегію
    _life = AppLifecycleListener(
      onResume: () async {
        final audio = context.read<AudioPlayerProvider>();
        final userN = context.read<UserNotifier>();

        // 1) Обновляем тип пользователя для поведения плеера из локального состояния
        audio.userType = getUserType(userN.user);

        // 2) 🔁 Дотягиваем приватный статус подписки (is_paid/paid_until) и обновляем тип
        try {
          await userN.refreshUserFromMe();
          audio.userType = getUserType(userN.user);
        } catch (_) {
          // не критично: если сеть недоступна, остаёмся на локальном статусе
        }

        // 3) Локал-first для плеера
        try {
          final hasLocal = await audio.hasSavedSession();
          if (!hasLocal) {
            await audio.hydrateFromServerIfAvailable();
          }
          await audio.ensurePrepared();
        } catch (_) {
          // ок, не критично
        }
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
    // Прибираємо нативний сплеш, щоб показати нашу анімацію
    FlutterNativeSplash.remove();

    final userNotifier = context.read<UserNotifier>();
    final audio = context.read<AudioPlayerProvider>();

    try {
      // 1) Мережа/кеш
      await ApiClient.init();

      // 2) Токени
      await AuthStore.I.restore();

      // 3) Авторизаційний інтерцептор (єдина точка)
      final dio = ApiClient.i();
      if (!_interceptorAttached) {
        dio.interceptors.removeWhere((it) => it is AuthInterceptor);
        dio.interceptors.add(AuthInterceptor(dio));
        _interceptorAttached = true;
      }

      // 4) Авто-логін за збереженими токенами
      await userNotifier.tryAutoLogin();

      // 4.1) 🔁 Приватный статус подписки (is_paid/paid_until) из /auth/me
      try {
        await userNotifier.refreshUserFromMe();
      } catch (_) {
        // мягко игнорируем сетевые ошибки на старте
      }

      // 5) Тип користувача для поведінки плеєра
      audio.userType = getUserType(userNotifier.user);
    } catch (_) {
      // залишаємося в гостьовому режимі — ок
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!_didPostFrameHeavy) {
        _didPostFrameHeavy = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            // ✅ Локал-first старт:
            await audio.restoreProgress();                // 1) підняти локаль
            final hasLocal = await audio.hasSavedSession();
            if (!hasLocal) {
              await audio.hydrateFromServerIfAvailable(); // 2) тягнути сервер ТІЛЬКИ якщо локалі немає
            }
            await audio.ensurePrepared();                 // 3) швидко підготувати плеєр
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
      // 🔄 Єдина анімація завантаження у всьому застосунку
      return Scaffold(
        backgroundColor: const Color(0xFF0B0B0C),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LoadingIndicator(size: 160), // ← Lottie через спільний віджет
              const SizedBox(height: 16),
              Text(
                'Завантаження…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ Повертаємо основний екран, а для тесту реклами (тільки debug)
    // поверх додаємо плаваючу кнопку, яка відкриває RewardTestScreen.
    return Stack(
      children: [
        const MainScreen(),
        if (kDebugMode)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              // Комментарий: кнопка видна только в debug-сборках
              heroTag: 'reward_test_fab',
              icon: const Icon(Icons.ondemand_video),
              label: const Text('Reward test'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RewardTestScreen()),
                );
              },
            ),
          ),
      ],
    );
  }
}
