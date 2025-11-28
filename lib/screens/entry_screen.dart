// ПУТЬ: lib/screens/entry_screen.dart

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:provider/provider.dart';

// ✅ ИМПОРТ ДЛЯ СВОРАЧИВАНИЯ (МИНИМИЗАЦИИ)
import 'package:flutter_app_minimizer_plus/flutter_app_minimizer_plus.dart';

// app
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // getUserType, UserType
import 'package:booka_app/screens/reward_test_screen.dart'; // 👈 екран теста рекламы

// core
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth_interceptor.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';
import 'package:booka_app/core/billing/billing_controller.dart';

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

    // 🔁 На возврат в фокус — простая local-first стратегия
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

        // 3) Local-first для плеера
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
            // ✅ Local-first старт:
            await audio.restoreProgress(); // 1) поднять локаль
            final hasLocal = await audio.hasSavedSession();
            if (!hasLocal) {
              // 2) тянуть с сервера ТОЛЬКО если локали нет
              await audio.hydrateFromServerIfAvailable();
            }
            await audio.ensurePrepared(); // 3) быстро подготовить плеер

            // 🚨 УСИЛЕНИЕ ИСПРАВЛЕНИЯ: Добавляем небольшую задержку (0 мс),
            // чтобы фантомный маршрут успел быть создан системой,
            // прежде чем мы его удалим. Это повышает надежность popUntil.
            await Future.delayed(Duration.zero);

            // 4. Удаляем любые фантомные маршруты, гарантируя, что EntryScreen является корнем стека.
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).popUntil((route) => route.isFirst);
              debugPrint('EntryScreen: Cleared navigation stack to first route.'); // 🚨 DEBUG
            }

          } catch (_) {
            // не критично для первого экрана
          }
        });
      }
    }
  }

  /// Диалог подтверждения выхода
  Future<bool> _showExitDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Вийти з додатку'),
          content: const Text('Ви дійсно хочете закрити додаток?'),
          actions: [
            // 🔄 КНОПКА "СКАСУВАТИ" -> СВОРАЧИВАНИЕ (МИНИМИЗАЦИЯ)
            TextButton(
              onPressed: () {
                // 1. Закрываем диалог (возвращаем false, чтобы PopScope знал, что выход не нужен)
                Navigator.of(ctx).pop(false);

                // 2. Сворачиваем приложение, если это Android
                if (Platform.isAndroid) {
                  // ✅ ИСПОЛЬЗУЕМ КОРРЕКТНЫЙ МЕТОД из FlutterAppMinimizerPlus
                  FlutterAppMinimizerPlus.minimizeApp();
                }
              },
              child: const Text('Згорнути і слухати далі'),
            ),

            // 🛑 КНОПКА "Вийти" -> ПОЛНОЕ ЗАКРЫТИЕ
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Вийти'),
            ),
          ],
        );
      },
    );

    // Возвращаем true только если была нажата кнопка "Вийти"
    return result == true;
  }

  /// Реальный выход из приложения:
  /// 1) показать короткое "спасибо"
  /// 2) вызвать dart:io.exit(0) для немедленного уничтожения процесса
  Future<void> _performAppExit() async {

    // Пытаемся показать snackbar с благодарностью
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Дякуємо, що були з Booka 💛'),
        duration: Duration(seconds: 1),
      ),
    );

    // Даём 1 секунду на отображение и завершение фоновых задач
    await Future.delayed(const Duration(seconds: 1));

    // 🚨 Немедленное и принудительное завершение процесса
    exit(0);
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

    // ✅ Возвращаем основной экран + перехват системной кнопки "Назад" через PopScope.
    return PopScope(
      // Это корневой экран: сами решаем, можно ли "выйти" из приложения
      canPop: false,
      onPopInvoked: (didPop) async {
        // didPop == true → Flutter уже сделал pop, нам ничего не надо
        if (didPop) return;

        // Показываем диалог подтверждения
        final shouldExit = await _showExitDialog();
        if (!shouldExit) return;

        // Пользователь нажал "Вийти" (Выход) → выполняем сценарий полного выхода
        await _performAppExit();
      },
      child: Stack(
        children: [
          const MainScreen(),

          // DEBUG Reward-test FAB (сейчас выключен, но легко включить при отладке):
          // if (kDebugMode)
          //   Positioned(
          //     right: 16,
          //     bottom: 16,
          //     child: FloatingActionButton.extended(
          //       // Кнопка видна только в debug-сборках
          //       heroTag: 'reward_test_fab',
          //       icon: const Icon(Icons.ondemand_video),
          //       label: const Text('Reward test'),
          //       onPressed: () {
          //         Navigator.of(context).push(
          //           MaterialPageRoute(builder: (_) => const RewardTestScreen()),
          //         );
          //       },
          //     ),
          //   ),
        ],
      ),
    );
  }
}