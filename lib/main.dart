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

// Экран для вознаграждения (Reward test)
import 'package:booka_app/screens/reward_test_screen.dart';

// Виджет для показа баннера поверх всех экранов
import 'package:booka_app/widgets/global_banner_injector.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

// Отслеживает жизненный цикл приложения (сворачивание, и т.д.)
class _LifecycleReactor with WidgetsBindingObserver {
  final AudioPlayerProvider audio;
  _LifecycleReactor(this.audio) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Сохраняем прогресс на сервер, если приложение сворачивается
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(audio.flushProgress());
    }
  }
}

_LifecycleReactor? _reactor;

// --- Логика межстраничной рекламы (Interstitial) ---

// ❗️ ВАЖНО: Замените тестовый ID на свой рабочий (PROD ID)
const String _interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712'; // Тестовый ID
InterstitialAd? _interstitialAd;

/// Загружает межстраничную рекламу
/// [ИЗМЕНЕНО] Теперь принимает audioProvider для управления паузой/воспроизведением
void _loadInterstitialAd(AudioPlayerProvider audioProvider) {
  debugPrint('[AD_MODE] Загрузка InterstitialAd...');
  InterstitialAd.load(
    adUnitId: _interstitialAdUnitId,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        debugPrint('[AD_MODE] InterstitialAd загружено.');
        _interstitialAd = ad;

        // Настраиваем колбэки на случай закрытия или ошибки
        _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            _loadInterstitialAd(audioProvider); // Загружаем следующую

            // --- [ИСПРАВЛЕНИЕ] ---
            // Возобновляем G, когда реклама закрыта
            audioProvider.play();
            // --- [КОНЕЦ ИСПРАВЛЕНИЯ] ---
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            _loadInterstitialAd(audioProvider); // Загружаем следующую

            // --- [ИСПРАВЛЕНИЕ] ---
            // Возобновляем, даже если реклама не показалась
            audioProvider.play();
            // --- [КОНЕЦ ИСПРАВЛЕНИЯ] ---
          },
        );
      },
      onAdFailedToLoad: (err) {
        debugPrint('[AD_MODE] Ошибка загрузки InterstitialAd: $err');
        _interstitialAd = null;
      },
    ),
  );
}
// --- Конец логики Interstitial ---


Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Центральный обработчик ошибок Flutter
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

    // Провайдеры создаём заранее
    final themeNotifier = ThemeNotifier();
    try {
      await themeNotifier.load();
    } catch (_) {}

    final userNotifier = UserNotifier();
    final audioProvider = AudioPlayerProvider();

    // Связываем AudioProvider с UserNotifier для обновления бесплатных секунд
    audioProvider.getFreeSeconds = () => userNotifier.freeSeconds;
    audioProvider.setFreeSeconds = (int v) => userNotifier.setFreeSeconds(v);

    // --- Настройка колбэков для AudioProvider ---

    // 1. Вызывается, когда закончились бесплатные секунды
    audioProvider.onCreditsExhausted = () {
      debugPrint('[AD_MODE] onCreditsExhausted: Секунды вышли.');
      // Открываем экран выбора (/rewarded)
      final currentRoute = ModalRoute.of(_navKey.currentContext!);
      if (currentRoute?.settings.name != '/rewarded') {
        _navKey.currentState?.pushNamed('/rewarded');
      }
    };

    // 2. Вызывается, если пользователь (с 0 сек) нажимает Play
    audioProvider.onNeedAdConsent = () async {
      debugPrint('[AD_MODE] onNeedAdConsent: Требуется согласие на рекламу.');
      // Показываем экран выбора и ЖДЕМ результат (true/false)
      final bool? userAgreed = await _navKey.currentState?.pushNamed<bool>('/rewarded');
      return userAgreed ?? false;
    };

    // 3. Вызывается по таймеру для показа межстраничной рекламы
    audioProvider.onShowIntervalAd = () async {
      debugPrint('[AD_MODE] onShowIntervalAd: Время показывать рекламу!');

      // --- [ИСПРАВЛЕНИЕ] ---
      // Сначала ставим G на паузу
      await audioProvider.pause();
      // --- [КОНЕЦ ИСПРАВЛЕНИЯ] ---

      if (_interstitialAd != null) {
        try {
          await _interstitialAd!.show();
          // Реклама показана. Воспроизведение возобновится
          // в колбэке onAdDismissedFullScreenContent (см. _loadInterstitialAd)
          _interstitialAd = null; // Помечаем как использованную
        } catch (e) {
          debugPrint('[AD_MODE] Ошибка показа InterstitialAd: $e');
          // --- [ИСПРАВЛЕНИЕ] ---
          // Если реклама не смогла показаться, СРАЗУ возобновляем G
          await audioProvider.play();
          // --- [КОНЕЦ ИСПРАВЛЕНИЯ] ---
        }
      } else {
        // Реклама не была готова.
        debugPrint('[AD_MODE] InterstitialAd не была готова. Загружаем...');
        _loadInterstitialAd(audioProvider); // Передаем audioProvider

        // --- [ИСПРАВЛЕНИЕ] ---
        // Реклама не готова, нечего показывать, возобновляем G
        await audioProvider.play();
        // --- [КОНЕЦ ИСПРАВЛЕНИЯ] ---
      }
    };
    // --- Конец настройки колбэков ---


    // Инициализация сетевого клиента
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

    // Предзагружаем первую рекламу
    // [ИЗМЕНЕНО] Передаем audioProvider
    _loadInterstitialAd(audioProvider);

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

    // Отложенная инициализация
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushService.instance.init(navigatorKey: _navKey);
      } catch (_) {}

      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          final audio = Provider.of<AudioPlayerProvider>(ctx, listen: false);

          // Если нет локальной сессии — загрузим с сервера
          final hasLocal = await audio.hasSavedSession();
          if (!hasLocal) {
            await audio.hydrateFromServerIfAvailable();
          }

          await audio.ensurePrepared();

          // Подписываемся на жизненный цикл приложения
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

          // --- ИСПРАВЛЕНИЕ ОШИБКИ ТИПОВ (УЖЕ БЫЛО) ---
          // Используем 'onGenerateRoute' для явного указания типа <bool>.
          routes: const <String, WidgetBuilder>{
            // '/rewarded': (_) => const RewardTestScreen(), // Оставлено пустым
          },
          onGenerateRoute: (RouteSettings settings) {
            if (settings.name == '/rewarded') {
              // Создаем маршрут, который ЯВНО возвращает <bool>
              return MaterialPageRoute<bool>(
                builder: (context) => const RewardTestScreen(),
                settings: settings,
              );
            }
            // Возвращаем null для стандартной обработки других маршрутов
            return null;
          },

          // Единый хост для баннера (поверх всех экранов)
          builder: (context, child) {
            final Widget safeChild = child ?? const SizedBox.shrink();
            return GlobalBannerInjector(
              child: safeChild,

              // Баннер AdMob
              adUnitId: 'ca-app-pub-3940256099942544/6300978111',
              adSize: AdSize.banner,

              // Навигация для CTA на экран Reward test
              navigatorKey: _navKey,
              ctaRouteName: '/rewarded',
            );
          },
        );
      },
    );
  }
}