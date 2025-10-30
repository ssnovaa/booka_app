// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/theme_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/entry_screen.dart';
import 'package:booka_app/screens/catalog_screen.dart' show routeObserver;

import 'package:booka_app/core/push/push_service.dart';
import 'package:booka_app/core/network/api_client.dart';

// 👇 Экран, который должен открываться (тот же, что у Reward test)
import 'package:booka_app/screens/reward_test_screen.dart';

// 👇 Глобальный инжектор баннера поверх всех экранов
import 'package:booka_app/widgets/global_banner_injector.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

/// Реактор на изменение жизненного цикла приложения
/// (русские комментарии по требованию пользователя)
class _LifecycleReactor with WidgetsBindingObserver {
  final AudioPlayerProvider audio;
  _LifecycleReactor(this.audio) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // При сворачивании/переходе в неактивное состояние — пушим прогресс на сервер
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(audio.flushProgress());
    }
  }
}

_LifecycleReactor? _reactor;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Централизованный перехват ошибок Flutter
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
    };

    // Инициализация фонового уведомления аудиоплеера (Android)
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
        androidNotificationChannelName: 'Booka — аудіо',
        androidNotificationOngoing: true,
      );
    } catch (_) {}

    // Провайдеры создаём заранее, чтобы можно было связать Audio ↔ User
    final themeNotifier = ThemeNotifier();
    try {
      await themeNotifier.load();
    } catch (_) {}

    final userNotifier = UserNotifier();
    final audioProvider = AudioPlayerProvider();

    // 🔗 Связка локального тикера секунд с UserNotifier (ВАЖНО: без сокращений)
    // Теперь AudioPlayerProvider сможет читать и обновлять freeSeconds у пользователя.
    audioProvider.getFreeSeconds = () => userNotifier.freeSeconds;
    audioProvider.setFreeSeconds = (int v) => userNotifier.setFreeSeconds(v);

    // Инициализация сетевого клиента
    try {
      await ApiClient.init();
    } catch (_) {}

    // Инициализация AdMob: сначала конфиг, затем initialize()
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          // при необходимости добавьте свои testDeviceIds
          testDeviceIds: <String>['129F9C64839B7C8761347820D44F1697'],
        ),
      );
    } catch (_) {}
    await MobileAds.instance.initialize();

    // Запуск приложения
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>.value(value: themeNotifier),
          ChangeNotifierProvider<UserNotifier>.value(value: userNotifier),
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audioProvider),
        ],
        child: const BookaApp(),
      ),
    );

    // Отложенная инициализация пуш-сервиса и аудио-провайдера
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushService.instance.init(navigatorKey: _navKey);
      } catch (_) {}

      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          final audio = Provider.of<AudioPlayerProvider>(ctx, listen: false);

          // Если до запуска не было локальной сессии — подтянем серверную.
          final hasLocal = await audio.hasSavedSession();
          if (!hasLocal) {
            await audio.hydrateFromServerIfAvailable();
          }

          await audio.ensurePrepared();

          // Подпишемся на жизненный цикл приложения один раз.
          _reactor ??= _LifecycleReactor(audio);
        }
      } catch (_) {}
    });
  }, (Object error, StackTrace stack) {
    FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
  });
}

class BookaApp extends StatelessWidget {
  const BookaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, _) {
        return MaterialApp(
          title: 'Booka — аудіокниги українською',
          debugShowCheckedModeBanner: false,
          themeMode: themeNotifier.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: Colors.deepPurple,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.deepPurple,
          ),
          home: const EntryScreen(),
          navigatorObservers: [routeObserver],
          navigatorKey: _navKey,

          // РЕГИСТРАЦИЯ ИМЕНОВАННОГО МАРШРУТА для реального экрана из Reward test
          routes: <String, WidgetBuilder>{
            '/rewarded': (_) => const RewardTestScreen(),
          },

          // ЕДИНЫЙ ХОСТ БАННЕРА ДЛЯ ВСЕГО ПРИЛОЖЕНИЯ
          // ВАЖНО: никаких доп. SizedBox-«резервов под баннер» в экранах.
          builder: (context, child) {
            final Widget safeChild = child ?? const SizedBox.shrink();
            return GlobalBannerInjector(
              child: safeChild,

              // Баннер AdMob (не связан с CTA)
              adUnitId: 'ca-app-pub-3940256099942544/6300978111',
              adSize: AdSize.banner,

              // Навигация для CTA строго на экран Reward test
              navigatorKey: _navKey,
              ctaRouteName: '/rewarded',
            );
          },
        );
      },
    );
  }
}
