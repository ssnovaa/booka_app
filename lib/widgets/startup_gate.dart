// lib/widgets/startup_gate.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/auth/auth_store.dart';
import 'package:booka_app/repositories/profile_repository.dart';
import 'package:booka_app/providers/audio_player_provider.dart';

/// Віджет-ворота старту: виконує початковий бутстрап
/// і переходить до [child], коли локаль готова (мережу не чекаємо).
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.child});

  final Widget child; // куди перейдемо після бутстрапу (наприклад, MainScreen)

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Запускаємо після першого кадру, щоб одразу показати Lottie-анімацію
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // ❌ Не прибираємо сплеш тут, зробимо це в кінці для плавності

    try {
      final audio = context.read<AudioPlayerProvider>();

      // ✅ 1. ПАРАЛЕЛЬНЕ виконання легких локальних задач (найважливіше прискорення)
      // Це займає мілісекунди, тому чекаємо завершення обох
      await Future.wait([
        AuthStore.I.restore(),
        audio.restoreProgress(),
      ]);

      final hasLocal = await audio.hasSavedSession();

      // ✅ 2. Вся важка робота з мережею йде у "фон" (ми НЕ чекаємо її через await)
      if (hasLocal) {
        // Запускаємо підготовку плеера, але НЕ ЧЕКАЄМО завершення тут.
        // Інтерфейс завантажиться, а плеер підтягнеться через частку секунди.
        // ignore: unawaited_futures
        audio.ensurePrepared().then((_) {
          debugPrint('[Startup] Audio prepared in background');
        }).catchError((e) {
          debugPrint('[Startup] Audio prepare error: $e');
        });

        // Дані профілю теж оновлюємо фоном
        // ignore: unawaited_futures
        ProfileRepository.I.loadMap(force: false);
        // ignore: unawaited_futures
        audio.hydrateFromServerIfAvailable();
      } else {
        // Якщо локальної сесії немає — теж пробуємо синхронізуватися у фоні
        _hydrateBackground(audio);
      }

    } catch (e) {
      debugPrint('[Startup] Error: $e');
    } finally {
      if (!mounted) return;

      // ✅ 3. Прибираємо нативний сплеш тільки коли все готово до показу UI
      FlutterNativeSplash.remove();

      // Відкриваємо додаток
      setState(() => _ready = true);
    }
  }

  // Допоміжний метод для фонової роботи (fire and forget)
  Future<void> _hydrateBackground(AudioPlayerProvider audio) async {
    try {
      await ProfileRepository.I.loadMap(force: true);
      final ok = await audio.hydrateFromServerIfAvailable();
      if (ok) {
        await audio.ensurePrepared();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    // Повноекранний прелоадер з Lottie
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              'assets/splash/booka_equalizer_loader.json',
              width: 160,
              repeat: true,
              // Оптимізація рендерингу кадрів для Lottie
              frameBuilder: (context, child, composition) {
                return child;
              },
            ),
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
}