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

// 👇 Экран согласия на режим «с рекламой»
import 'package:booka_app/screens/reward_test_screen.dart';

// 👇 Глобальный инжектор баннера поверх всех экранов
import 'package:booka_app/widgets/global_banner_injector.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

/// Реактор на изменение жизненного цикла приложения
class _LifecycleReactor with WidgetsBindingObserver {
  final AudioPlayerProvider audio;
  _LifecycleReactor(this.audio) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(audio.flushProgress());
    }
  }
}

_LifecycleReactor? _reactor;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
    };

    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
        androidNotificationChannelName: 'Booka — аудіо',
        androidNotificationOngoing: true,
      );
    } catch (_) {}

    // Провайдеры создаём заранее, чтобы связать Audio ↔ User
    final themeNotifier = ThemeNotifier();
    try {
      await themeNotifier.load();
    } catch (_) {}

    final userNotifier = UserNotifier();
    final audioProvider = AudioPlayerProvider();

    // Связка секунд с UserNotifier
    audioProvider.getFreeSeconds = () => userNotifier.freeSeconds;
    audioProvider.setFreeSeconds = (int v) => userNotifier.setFreeSeconds(v);

    // Инициализация сети
    try {
      await ApiClient.init();
    } catch (_) {}

    // Инициализация AdMob
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: <String>['129F9C64839B7C8761347820D44F1697'],
        ),
      );
    } catch (_) {}
    await MobileAds.instance.initialize();

    // === ВАЖНО: назначаем колбэки провайдера АУДИО ===

    // 1) Экран согласия «продолжить с рекламой»
    audioProvider.onNeedAdConsent = () async {
      final ctx = _navKey.currentContext;
      if (ctx == null) return false;

      final result = await Navigator.of(ctx).push<bool>(
        MaterialPageRoute(
          builder: (_) => const RewardTestScreen(),
          fullscreenDialog: true,
        ),
      );

      return result == true;
    };

    // 2) Автопоказ межстраничной рекламы раз в 10 минут (ad-mode)
    audioProvider.onShowIntervalAd = () async {
      await _showInterstitialAd(audioProvider);
    };

    // 3) Фоллбек: если секунд нет и ad-consent не получен — отправим на тот же экран
    audioProvider.onCreditsExhausted = () {
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      // Не плодим копии, если уже открыто
      if (ModalRoute.of(ctx)?.settings.name == '/rewarded') return;
      Navigator.of(ctx).pushNamed('/rewarded');
    };

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

    // Отложённые инициализации
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushService.instance.init(navigatorKey: _navKey);
      } catch (_) {}

      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          final audio = Provider.of<AudioPlayerProvider>(ctx, listen: false);

          final hasLocal = await audio.hasSavedSession();
          if (!hasLocal) {
            await audio.hydrateFromServerIfAvailable();
          }

          await audio.ensurePrepared();

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

          // Именованный маршрут на экран согласия
          routes: <String, WidgetBuilder>{
            '/rewarded': (_) => const RewardTestScreen(),
          },

          // Единый хост баннера
          builder: (context, child) {
            final Widget safeChild = child ?? const SizedBox.shrink();
            return GlobalBannerInjector(
              child: safeChild,
              adUnitId: 'ca-app-pub-3940256099942544/6300978111', // тестовый баннер
              adSize: AdSize.banner,
              navigatorKey: _navKey,
              ctaRouteName: '/rewarded',
            );
          },
        );
      },
    );
  }
}

/// Показываем межстраничную рекламу для ad-mode.
/// На время показа ставим плеер на паузу и затем возвращаем воспроизведение.
Future<void> _showInterstitialAd(AudioPlayerProvider audio) async {
  final wasPlaying = audio.isPlaying;
  if (wasPlaying) {
    await audio.pause();
  }

  final completer = Completer<void>();

  InterstitialAd.load(
    adUnitId: 'ca-app-pub-3940256099942544/1033173712', // тестовый interstitial
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (InterstitialAd ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            if (wasPlaying) {
              unawaited(audio.play());
            }
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            if (wasPlaying) {
              unawaited(audio.play());
            }
            if (!completer.isCompleted) completer.complete();
          },
        );

        ad.show(); // пользователь закроет — колбэк сработает
      },
      onAdFailedToLoad: (LoadAdError error) {
        // Не критично: просто продолжаем воспроизведение.
        if (wasPlaying) {
          unawaited(audio.play());
        }
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );

  return completer.future;
}
