// lib/main.dart (РАБОЧИЙ + НАСТРОЙКИ ШТОРКИ И ЛОКСКРИНА)
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

import 'package:booka_app/core/push/push_service.dart';
import 'package:booka_app/core/network/api_client.dart';

// 👇 Глобальный инжектор баннера поверх всех экранов
import 'package:booka_app/widgets/global_banner_injector.dart';

// 👇 НОВЫЙ БИЛЛИНГ
import 'package:booka_app/core/billing/billing_service.dart';
import 'package:booka_app/core/billing/billing_controller.dart';

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

    // При возврате в приложение — обновляем пользователя
    if (state == AppLifecycleState.resumed) {
      try {
        userNotifier.fetchCurrentUser();
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

    // 🚀 Запускаємо важкі ініціалізації паралельно, не блокуючи runApp
    final justAudioInit = _initJustAudioBackground();
    final themeLoad = _safeThemeLoad(themeNotifier);
    final apiInit = _safeApiInit();
    final adsInit = _initMobileAds();

    // ✅ Стартуємо ліниві задачі, не чекаючи завершення
    unawaited(justAudioInit);
    unawaited(themeLoad);
    unawaited(apiInit);
    unawaited(adsInit);

    // === ВАЖНО: назначаем колбэки провайдера АУДИО ===

    // 2) Автопоказ межстраничной рекламы раз в 10 минут (ad-mode)
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
          // Сервис — НЕ ChangeNotifier, поэтому используется обычный Provider.
          // Использование .value, так как экземпляр уже создан выше.
          Provider<BillingService>.value(
            value: billingService,
          ),

          // Контроллер — ChangeNotifier, работает с UI
          ChangeNotifierProvider<BillingController>(
            // Используем 'create' и 'context.read' для получения
            // BillingService, который уже есть в дереве
            create: (context) => BillingController(
              service: context.read<BillingService>(), // ⬅️ ИСПРАВЛЕНО
              userNotifier: userNotifier,
              audioPlayerProvider: audioProvider,
            ),
          ),
        ],
        child: const BookaApp(),
      ),
    );

    // Отложённые инициализации
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // 🕒 Чекаємо мережевую ініціалізацію перед пушами/аудіо
        await apiInit;
      } catch (_) {}

      try {
        await PushService.instance.init(
          navigatorKey: _navKey,
          userNotifier: userNotifier,
        );
      } catch (_) {}

      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          final audio =
          Provider.of<AudioPlayerProvider>(ctx, listen: false);
          final user = Provider.of<UserNotifier>(ctx, listen: false);

          // ⛔ РАНЬШЕ ТУТ БЫЛО billingService.attachContext(ctx);
          // Для новой структуры биллинга это больше не нужно.

          final hasLocal = await audio.hasSavedSession();
          if (!hasLocal) {
            try {
              await user.fetchCurrentUser();
            } catch (e) {
              // ігноруємо, якщо немає мережі
            }
            await audio.hydrateFromServerIfAvailable();
          }

          await audio.ensurePrepared();

          _reactor ??= _LifecycleReactor(audio, user);
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
      androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
      androidNotificationChannelName: 'Booka — аудіо',
      androidNotificationOngoing: true,
      notificationColor: const Color(0xFF6750A4),
      androidNotificationIcon: 'mipmap/ic_launcher',
      rewindInterval: const Duration(seconds: 10),
      fastForwardInterval: const Duration(seconds: 30),
      preloadArtwork: true,
    );
  } catch (_) {}
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
        testDeviceIds: <String>['129F9C64839B7C8761347820D44F1697'],
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

          // 👇 РЕГИСТРАЦИЯ ИМЕНОВАННОГО МАРШРУТА ДЛЯ РАБОЧЕГО ЭКРАНА НАГРАДЫ
          routes: <String, WidgetBuilder>{
            '/rewarded': (_) => const RewardTestScreen(),
          },

          // Единый хост баннера (без глобального WillPopScope)
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

Future<bool> _openRewardScreen() async {
  NavigatorState? nav = _navKey.currentState;

  // 🔄 Навигатор может быть недоступен в момент вызова (например, сразу после
  // старта приложения или во время горячей навигации). Пробуем получить его
  // несколько раз с небольшими задержками, прежде чем сдаться.
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
/// На время показа ставим плеер на паузу и затем возвращаем воспроизведение.
Future<void> _showInterstitialAd(AudioPlayerProvider audio) async {
  if (_interstitialInProgress != null && !_interstitialInProgress!.isCompleted) {
    return _interstitialInProgress!.future; // уже показываем, не запускаем вторую
  }

  final wasPlaying = audio.isPlaying;
  if (wasPlaying) {
    await audio.pause();
  }

  final completer = _interstitialInProgress = Completer<void>();

  void completeOnce() {
    if (!completer.isCompleted) {
      completer.complete();
    }
    _interstitialInProgress = null;
  }

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
            completeOnce();
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            if (wasPlaying) {
              unawaited(audio.play());
            }
            completeOnce();
          },
        );

        ad.show(); // пользователь закроет — колбэк сработает
      },
      onAdFailedToLoad: (LoadAdError error) {
        // Не критично: просто продолжаем воспроизведение.
        if (wasPlaying) {
          unawaited(audio.play());
        }
        completeOnce();
      },
    ),
  );

  return completer.future;
}