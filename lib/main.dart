// lib/main.dart (ИСПРАВЛЕННЫЙ: Ad-Mode Notification + Resume Logic + AppToast + Deep Links)
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ᐊ===== PUSH

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/theme_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/entry_screen.dart';
import 'package:booka_app/screens/catalog_screen.dart' show routeObserver;

// 👇 Экран согласия / режима с рекламой (рабочий, не тестовый)
import 'package:booka_app/screens/reward_test_screen.dart';
// 🔥 ДОБАВЛЕНО: Экран подписок для перехода из пуша
import 'package:booka_app/screens/subscriptions_screen.dart';

import 'package:booka_app/core/push/push_service.dart';
import 'package:booka_app/core/network/api_client.dart';

// 👇 Глобальный инжектор баннера поверх всех экранов
import 'package:booka_app/widgets/global_banner_injector.dart';

// 👇 НОВЫЙ БИЛЛИНГ
import 'package:booka_app/core/billing/billing_service.dart';
import 'package:booka_app/core/billing/billing_controller.dart';

// 👇 1. Добавлено: Импорт для красивых уведомлений
import 'package:booka_app/core/ui/app_toast.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
bool _rewardScreenOpen = false; // защита от дублирующихся пушей
Completer<void>? _interstitialInProgress; // защита от параллельных interstitial

/// Реактор на изменение жизненного цикла приложения
class _LifecycleReactor with WidgetsBindingObserver {
  final AudioPlayerProvider audio;
  // ᐊ===== UserNotifier
  final UserNotifier userNotifier;

  _LifecycleReactor(this.audio, this.userNotifier) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(audio.flushProgress());
    }

    // При возврате в приложение — обновляем пользователя и проверяем рекламу
    if (state == AppLifecycleState.resumed) {
      try {
        // 🔥 ОПТИМИЗАЦИЯ: запускаем без await, чтобы не фризить UI
        userNotifier.fetchCurrentUser();

        // 👇 НОВОЕ: Если реклама должна была сработать пока телефон спал — показываем сейчас
        audio.checkPendingAdOnResume();

      } catch (e) {
        // игнорируем ошибку (нет сети и т.п.)
      }
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

    // ✅ ВАЖНО: Инициализируем аудио СТРОГО ПЕРВЫМ и с await.
    // Это гарантирует, что канал уведомлений будет создан до старта плеера.
    await _initJustAudioBackground();

    // Провайдери створюємо заздалегідь, щоб зв'язати Audio ↔ User
    final themeNotifier = ThemeNotifier();
    final userNotifier = UserNotifier();
    final audioProvider = AudioPlayerProvider();

    // 👇 Створюємо екземпляр нового сервісу білінгу (core/billing)
    final billingService = BillingService();

    // Зв'язка секунд з UserNotifier
    audioProvider.getFreeSeconds = () => userNotifier.freeSeconds;
    audioProvider.setFreeSeconds = (int v) {
      userNotifier.setFreeSeconds(v);
      audioProvider.onExternalFreeSecondsUpdated(v);
    };

    // 🚀 Запускаємо інші важкі ініціалізації паралельно
    final themeLoad = _safeThemeLoad(themeNotifier);
    final apiInit = _safeApiInit();
    final adsInit = _initMobileAds();

    // ✅ Стартуємо ліниві задачі, не чекаючи завершення
    unawaited(themeLoad);
    unawaited(apiInit);
    unawaited(adsInit);

    // === ВАЖНО: назначаем колбэки провайдера АУДИО ===

    // 2) Автопоказ межстраничной рекламы раз в интервал (ad-mode)
    audioProvider.onShowIntervalAd = () async {
      await _showInterstitialAd(audioProvider);
    };

    // 3) Открываем экран продолжения, когда секунды исчерпаны
    audioProvider.onCreditsExhausted = () {
      unawaited(_openRewardScreen());
    };

    // 4) Запрос согласия на ad-mode, когда секунд нет
    audioProvider.onNeedAdConsent = () => _openRewardScreen();

    // Запуск приложения
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>.value(value: themeNotifier),
          ChangeNotifierProvider<UserNotifier>.value(value: userNotifier),
          ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: audioProvider,
          ),

          // 👇 НОВЫЙ БИЛЛИНГ В ДЕРЕВЕ
          Provider<BillingService>.value(
            value: billingService,
          ),

          // Контроллер — ChangeNotifier, работает с UI
          ChangeNotifierProvider<BillingController>(
            create: (context) => BillingController(
              service: context.read<BillingService>(),
              userNotifier: userNotifier,
              audioPlayerProvider: audioProvider,
            ),
          ),
        ],
        child: const BookaApp(),
      ),
    );

    // 🔥 ОПТИМИЗАЦИЯ СТАРТА
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // 🕒 Чекаємо мережевую ініціалізацію перед пушами
        await apiInit;
      } catch (_) {}

      try {
        // Инициализация пушей (не блокирует UI)
        await PushService.instance.init(
          navigatorKey: _navKey,
          userNotifier: userNotifier,
        );
      } catch (_) {}

      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          // Инициализируем реактор жизненного цикла
          _reactor ??= _LifecycleReactor(audioProvider, userNotifier);
        }
      } catch (_) {}
    });
  }, (Object error, StackTrace stack) {
    FlutterError.presentError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  });
}

Future<void> _initJustAudioBackground() async {
  try {
    // ⚙️ Налаштування зовнішнього вигляду плеєра (шторка і локскрін)
    await JustAudioBackground.init(
      // 👇 Якщо міняли раніше ID, переконайтеся, що тут актуальний
      androidNotificationChannelId: 'com.booka.audioplayer.channel.audio_v2',
      androidNotificationChannelName: 'Booka — аудіо',
      androidNotificationOngoing: true,
      notificationColor: const Color(0xFF6750A4),

      // ✅ ПРАВИЛЬНА ІКОНКА (силует для шторки), щоб плеер не показував Spotify
      androidNotificationIcon: 'drawable/ic_stat_notify',

      rewindInterval: const Duration(seconds: 10),
      fastForwardInterval: const Duration(seconds: 30),
      preloadArtwork: true,
    );
  } catch (e) {
    debugPrint('[AUDIO] Init failed: $e');
  }
}

Future<void> _safeThemeLoad(ThemeNotifier notifier) async {
  try {
    await notifier.load();
  } catch (_) {}
}

Future<void> _safeApiInit() async {
  try {
    await ApiClient.init();
  } catch (_) {}
}

Future<void> _initMobileAds() async {
  try {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: <String>[],
      ),
    );
  } catch (_) {}

  try {
    await MobileAds.instance.initialize();
  } catch (_) {}
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

          // 👇 РЕГИСТРАЦИЯ ИМЕНОВАННЫХ МАРШРУТОВ
          routes: <String, WidgetBuilder>{
            '/rewarded': (_) => const RewardTestScreen(),
            '/subscriptions': (_) => const SubscriptionsScreen(), // ✅ Добавлено
          },

          // Единый хост баннера (без глобального WillPopScope)
          builder: (context, child) {
            final Widget safeChild = child ?? const SizedBox.shrink();
            return GlobalBannerInjector(
              child: safeChild,
              adUnitId: 'ca-app-pub-9743644418783616/5671045607', // НЕ тестовый баннер
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

Future<bool> _openRewardScreen() async {
  NavigatorState? nav = _navKey.currentState;

  if (nav == null) {
    for (var i = 0; i < 5 && nav == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      nav = _navKey.currentState;
    }
  }

  if (nav == null) {
    debugPrint('[REWARD][ERR] navigator not ready → skip open');
    return false;
  }

  if (_rewardScreenOpen) return false;
  _rewardScreenOpen = true;

  try {
    debugPrint('[REWARD] opening reward screen…');
    final result = await nav.pushNamed('/rewarded');
    return result == true;
  } catch (e, st) {
    debugPrint('[REWARD][ERR] open reward failed: $e\n$st');
    return false;
  } finally {
    _rewardScreenOpen = false;
  }
}

/// Показываем межстраничную рекламу для ad-mode.
/// С добавлением визуального уведомления и корректным возобновлением плеера.
Future<void> _showInterstitialAd(AudioPlayerProvider audio) async {
  if (_interstitialInProgress != null && !_interstitialInProgress!.isCompleted) {
    return _interstitialInProgress!.future;
  }

  final wasPlaying = audio.isPlaying;
  if (wasPlaying) {
    // ВАЖЛИВО: pause(), а не stop(), щоб не ламати шторку
    await audio.pause();
  }

  // 👇 2. ОНОВЛЕНО: Используем AppToast вместо SnackBar
  final context = _navKey.currentContext;
  if (context != null && context.mounted) {
    AppToast.showAdStarting(context);
  }

  final completer = _interstitialInProgress = Completer<void>();

  void completeOnce() {
    if (!completer.isCompleted) {
      completer.complete();
    }
    _interstitialInProgress = null;
  }

  InterstitialAd.load(
    adUnitId: 'ca-app-pub-9743644418783616/7443292271', // тестовый interstitial
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (InterstitialAd ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            // 🟢 2. ВОЗОБНОВЛЯЕМ ВОСПРОИЗВЕДЕНИЕ
            if (wasPlaying) {
              unawaited(audio.play());
            }
            completeOnce();
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            // Если не смогли показать - тоже играем
            if (wasPlaying) {
              unawaited(audio.play());
            }
            completeOnce();
          },
        );

        ad.show();
      },
      onAdFailedToLoad: (LoadAdError error) {
        debugPrint('[AD] Failed to load: $error');
        // Если ошибка — просто продолжаем играть
        if (wasPlaying) {
          unawaited(audio.play());
        }
        completeOnce();
      },
    ),
  );

  return completer.future;
}