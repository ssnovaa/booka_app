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

// ------------------- 👇 [ВИПРАВЛЕННЯ 1] 👇 -------------------
//
// Логіка для завантаження та показу МІЖСТОРІНКОВОЇ реклами (Interstitial).
// AudioPlayerProvider буде викликати onShowIntervalAd, а ми покажемо цю рекламу.
//
// ❗️ Використовуйте свій PROD ID замість тестового
const String _interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712'; // Тестовий ID
InterstitialAd? _interstitialAd;

/// Завантажує нову міжсторінкову рекламу
void _loadInterstitialAd() {
  debugPrint('[AD_MODE] Завантаження InterstitialAd...');
  InterstitialAd.load(
    adUnitId: _interstitialAdUnitId,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        debugPrint('[AD_MODE] InterstitialAd завантажено.');
        _interstitialAd = ad;
        // Налаштовуємо логіку на випадок закриття/помилки,
        // щоб одразу завантажити наступну рекламу
        _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            _loadInterstitialAd(); // Завантажуємо наступну
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            _loadInterstitialAd(); // Завантажуємо наступну
          },
        );
      },
      onAdFailedToLoad: (err) {
        debugPrint('[AD_MODE] Помилка завантаження InterstitialAd: $err');
        _interstitialAd = null;
      },
    ),
  );
}
// ------------------- 👆 [КІНЕЦЬ ВИПРАВЛЕННЯ 1] 👆 -------------------


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

    // ------------------- 👇 [ВИПРАВЛЕННЯ 2] 👇 -------------------
    //
    // Призначаємо колбеки-ДІЇ для AudioPlayerProvider.
    //
    // 1. Що робити, коли секунди закінчилися (плеєр зупинився)
    audioProvider.onCreditsExhausted = () {
      debugPrint('[AD_MODE] onCreditsExhausted: Секунди вийшли. Потрібне рішення.');
      // Відкриваємо екран вибору (той самий /rewarded)
      // Перевіряємо, щоб не відкрити 10 разів поспіль
      final currentRoute = ModalRoute.of(_navKey.currentContext!);
      if (currentRoute?.settings.name != '/rewarded') {
        _navKey.currentState?.pushNamed('/rewarded');
      }
    };

    // 2. Що робити, якщо користувач (з 0 сек) тисне Play
    audioProvider.onNeedAdConsent = () async {
      debugPrint('[AD_MODE] onNeedAdConsent: Потрібна згода на рекламу.');
      // Показуємо екран вибору і ЧЕКАЄМО на результат (true/false)
      final bool? userAgreed = await _navKey.currentState?.pushNamed<bool>('/rewarded');
      // Повертаємо true, якщо користувач натиснув "Продовжити з рекламою"
      return userAgreed ?? false;
    };

    // 3. Що робити, коли спрацював таймер (наприклад, 3 хв)
    audioProvider.onShowIntervalAd = () async {
      debugPrint('[AD_MODE] onShowIntervalAd: Час показувати рекламу!');
      if (_interstitialAd != null) {
        try {
          await _interstitialAd!.show();
          // Рекламу показано, вона закриється і в
          // onAdDismissedFullScreenContent завантажиться нова.
          _interstitialAd = null; // Позначаємо як використану
        } catch (e) {
          debugPrint('[AD_MODE] Помилка показу InterstitialAd: $e');
        }
      } else {
        // Реклама не була готова. Просто завантажуємо наступну.
        debugPrint('[AD_MODE] InterstitialAd не була готова. Завантажуємо...');
        _loadInterstitialAd();
      }
    };
    // ------------------- 👆 [КІНЕЦЬ ВИПРАВЛЕННЯ 2] 👆 -------------------


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

    // ------------------- 👇 [ВИПРАВЛЕННЯ 3] 👇 -------------------
    // Завантажуємо першу рекламу заздалегідь
    _loadInterstitialAd();
    // ------------------- 👆 [КІНЕЦЬ ВИПРАВЛЕННЯ 3] 👆 -------------------

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

          // Якщо до запуску не було локальної сесії — підтягнемо серверну.
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
            // Важливо: переконайтеся, що RewardTestScreen повертає
            // true/false через Navigator.pop(true) або Navigator.pop(false)
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