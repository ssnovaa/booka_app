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
    // Прибираємо нативний сплеш — тепер буде видно наш лоадер
    FlutterNativeSplash.remove();

    try {
      // 1) Відновлення токенів / авторизації
      await AuthStore.I.restore();

      // 2) Локал-first підготовка плеєра
      final audio = context.read<AudioPlayerProvider>();

      // підняти локальний прогрес
      await audio.restoreProgress();

      // якщо локальна сесія є — одразу готуємо плеєр і відпускаємо UI
      final hasLocal = await audio.hasSavedSession();
      if (hasLocal) {
        await audio.ensurePrepared();

        // сервер — у фоні (статистика/резерв)
        unawaited(ProfileRepository.I.loadMap(force: false));
        unawaited(audio.hydrateFromServerIfAvailable());
      } else {
        // локалі немає: UI не блокуємо, мережеву гідратацію запускаємо у фоні
        unawaited(() async {
          try {
            await ProfileRepository.I.loadMap(force: true);
          } catch (_) {}
          final ok = await audio.hydrateFromServerIfAvailable();
          if (ok) {
            try {
              await audio.ensurePrepared();
            } catch (_) {}
          }
        }());
      }
    } catch (_) {
      // М'яко ігноруємо помилки бутстрапу — все одно пропускаємо в додаток
    } finally {
      if (!mounted) return;
      setState(() => _ready = true);
    }
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
