// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/theme_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/entry_screen.dart';
import 'package:booka_app/screens/catalog_screen.dart' show routeObserver; // RouteObserver для событий навигации

// ⬇️ Push
import 'package:booka_app/core/push/push_service.dart';

// ⬇️ Сеть — ранняя инициализация, чтобы пуш-сервис мог работать
import 'package:booka_app/core/network/api_client.dart';

// ⬇️ Прелоадер-ворота старта (Lottie)
import 'package:booka_app/widgets/startup_gate.dart';

// Глобальный ключ навигатора — чтобы открывать экраны из пушей
final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Всё — в одной зоне, чтобы ловить необработанные ошибки.
  runZonedGuarded(() async {
    // ВАЖНО: инициализируем биндинг и удерживаем нативный сплэш,
    // чтобы избежать "чёрного экрана" до первого кадра Flutter.
    final binding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: binding);

    // Прокидываем Flutter-ошибки в текущую зону
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
    };

    // 1) Фоновое аудио до runApp
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
        androidNotificationChannelName: 'Booka Audio',
        androidNotificationOngoing: true,
      );
    } catch (e, st) {
      debugPrint('JustAudioBackground.init failed: $e\n$st');
    }

    // 2) Провайдеры, требующие предварительной инициализации
    final themeNotifier = ThemeNotifier();
    try {
      await themeNotifier.load(); // подгрузим сохранённый режим (light/dark/system)
    } catch (e, st) {
      debugPrint('ThemeNotifier.load failed: $e\n$st');
    }

    // User & Audio — без ранних tryAutoLogin/restoreProgress.
    // Дальше это сделает EntryScreen (а прелоадер покажет StartupGate).
    final userNotifier = UserNotifier();
    final audioProvider = AudioPlayerProvider();

    // 3) Сеть — инициализация ДО пушей
    try {
      await ApiClient.init();
    } catch (e, st) {
      debugPrint('ApiClient.init failed: $e\n$st');
    }

    // 4) Запуск приложения
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

    // 5) Push — инициализация FCM (разрешения, токен, диплинки) ПОСЛЕ runApp,
    // когда уже есть navigatorKey и готов ApiClient
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushService.instance.init(navigatorKey: _navKey);
      } catch (e, st) {
        debugPrint('PushService.init failed: $e\n$st');
      }
    });
  }, (Object error, StackTrace stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class BookaApp extends StatelessWidget {
  const BookaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, _) {
        return MaterialApp(
          title: 'Booka',
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
          // ⤵️ ПЕРЕХОД ЧЕРЕЗ ВОРОТА С ПРЕЛОАДЕРОМ (Lottie)
          // StartupGate сам снимет нативный сплэш и покажет лоадер,
          // пока EntryScreen делает bootstrap (Auth/Dio/Player).
          home: const StartupGate(
            child: EntryScreen(),
          ),
          navigatorObservers: [routeObserver],
          // ⬇️ важно: тот же ключ, что и в PushService
          navigatorKey: _navKey,
        );
      },
    );
  }
}
