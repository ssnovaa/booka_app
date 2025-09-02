// lib/widgets/startup_gate.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/auth/auth_store.dart';
import 'package:booka_app/repositories/profile_repository.dart';
import 'package:booka_app/providers/audio_player_provider.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.child});

  final Widget child; // куда перейдём после бутстрапа (например, MainScreen)

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Запускаем после первого кадра, чтобы сразу показать Lottie
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // снимаем нативный сплэш — теперь будет виден наш лоадер
    FlutterNativeSplash.remove();

    try {
      // 1) Токены/авторизация
      await AuthStore.I.restore();

      // 2) Профиль/текущая сессия
      await ProfileRepository.I.loadMap(force: true);

      // 3) Гидратация плеера (если провайдер смонтирован выше по дереву)
      final app = context.read<AudioPlayerProvider>();
      await app.hydrateFromServerIfAvailable();
      await app.ensurePrepared();
    } catch (_) {
      // мягко игнорируем — всё равно пустим в приложение
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    // Полноэкранный прелоадер с Lottie
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
