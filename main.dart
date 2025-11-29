// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ Додано для SystemChrome
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ Додано для ініціалізації
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/theme_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/entry_screen.dart';
import 'package:booka_app/screens/catalog_screen.dart' show routeObserver;

// 👇 Екран згоди / режиму з рекламою
import 'package:booka_app/screens/reward_test_screen.dart';

import 'package:booka_app/core/push/push_service.dart';
import 'package:booka_app/core/network/api_client.dart';

// 👇 Глобальний інжектор банера
import 'package:booka_app/widgets/global_banner_injector.dart';

// 👇 Білінг
import 'package:booka_app/core/billing/billing_service.dart';
import 'package:booka_app/core/billing/billing_controller.dart';

// Локалізація (обов'язково для Android меню)
import 'package:flutter_localizations/flutter_localizations.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
Completer<void>? _interstitialInProgress; // защита от параллельных interstitial

/// Реактор на зміну життєвого циклу
class _LifecycleReactor with WidgetsBindingObserver {
  final AudioPlayerProvider audio;
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

    if (state == AppLifecycleState.resumed) {
      try {
        userNotifier.fetchCurrentUser();
      } catch (e) {
        // ігноруємо
      }
    }
  }
}

_LifecycleReactor? _reactor;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ Фіксація орієнтації (портретна)
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
    };

    // ✅ Ініціалізація Firebase (безпечна, без firebase_options.dart)
    // На Android воно підтягне google-services.json автоматично.
    try {
      await Firebase.initializeApp();
    } catch (_) {}

    // 🎵 НАЛАШТУВАННЯ ПЛЕЄРА (ШТОРКА ТА ЛОК-СКРІН)
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
        androidNotificationChannelName: 'Booka — аудіо',
        androidNotificationOngoing: true,

        // 🎨 Зовнішній вигляд (колір іконок та прогрес-бару)
        notificationColor: const Color(0xFF6750A4),
        androidNotificationIcon: 'mipmap/ic_launcher',

        // ⏩ КНОПКИ ПЕРЕМОТКИ (Замість "Prev/Next" на локскріні)
        rewindInterval: const Duration(seconds: 10),
        fastForwardInterval: const Duration(seconds: 30),

        // 🖼️ Завантаження обкладинок
        preloadArtwork: true,
      );
    } catch (_) {}

    // Провайдери
    final themeNotifier = ThemeNotifier();
    try {
      await themeNotifier.load();
    } catch (_) {}

    final userNotifier = UserNotifier();
    final audioProvider = AudioPlayerProvider();
    final billingService = BillingService();

    // Зв'язка секунд
    audioProvider.getFreeSeconds = () => userNotifier.freeSeconds;
    audioProvider.setFreeSeconds = (int v) {
      userNotifier.setFreeSeconds(v);
      audioProvider.onExternalFreeSecondsUpdated(v);
    };

    // Мережа
    try {
      await ApiClient.init();
    } catch (_) {}

    // Реклама
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: <String>['129F9C64839B7C8761347820D44F1697'],
        ),
      );
    } catch (_) {}
    await MobileAds.instance.initialize();

    // Колбек показу реклами
    audioProvider.onShowIntervalAd = () async {
      await _showInterstitialAd(audioProvider);
    };

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>.value(value: themeNotifier),
          ChangeNotifierProvider<UserNotifier>.value(value: userNotifier),
          ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: audioProvider,
          ),
          Provider<BillingService>.value(
            value: billingService,
          ),
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

    // Відкладена ініціалізація
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushService.instance.init(
          navigatorKey: _navKey,
          userNotifier: userNotifier,
        );
      } catch (_) {}

      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          final audio = Provider.of<AudioPlayerProvider>(ctx, listen: false);
          final user = Provider.of<UserNotifier>(ctx, listen: false);

          final hasLocal = await audio.hasSavedSession();
          if (!hasLocal) {
            try {
              await user.fetchCurrentUser();
            } catch (e) {}
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

          // Локалізація (стандартна)
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('uk', 'UA'),
            Locale('en', 'US'),
          ],

          home: const EntryScreen(),
          navigatorObservers: [routeObserver],
          navigatorKey: _navKey,

          routes: <String, WidgetBuilder>{
            '/rewarded': (_) => const RewardTestScreen(),
          },

          builder: (context, child) {
            final Widget safeChild = child ?? const SizedBox.shrink();
            return GlobalBannerInjector(
              child: safeChild,
              adUnitId: 'ca-app-pub-3940256099942544/6300978111',
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
    adUnitId: 'ca-app-pub-3940256099942544/1033173712',
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
        ad.show();
      },
      onAdFailedToLoad: (LoadAdError error) {
        if (wasPlaying) {
          unawaited(audio.play());
        }
        completeOnce();
      },
    ),
  );

  return completer.future;
}