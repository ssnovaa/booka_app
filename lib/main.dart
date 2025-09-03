// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
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

// Глобальный ключ навигатора — чтобы открывать экраны из пушей
final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Всё — в одной зоне, чтобы ловить необработанные ошибки.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

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

    // User & Audio: без ранних tryAutoLogin/restoreProgress.
    // Всё это централизовано в EntryScreen._bootstrap().
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

    // 5) Post-frame: пуши и ПРЕДЗАГРУЗКА ПЛЕЕРА
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Инициализация FCM (разрешения, токен, диплинки)
        await PushService.instance.init(navigatorKey: _navKey);
      } catch (e, st) {
        debugPrint('PushService.init failed: $e\n$st');
      }

      // 🔥 ВАЖНО: как только дерево виджетов поднялось — аккуратно «прогреваем» плеер.
      // 1) пробуем подтянуть серверный прогресс (если юзер уже залогинен)
      // 2) в любом случае готовим источник из локального current_listen/карты прогресса
      try {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          final audio = Provider.of<AudioPlayerProvider>(ctx, listen: false);
          // сначала тихо попробуем гидратацию с бэка
          unawaited(audio.hydrateFromServerIfAvailable());
          // затем — гарантированно подготовим источник (idempotent)
          unawaited(audio.ensurePrepared());
        }
      } catch (e, st) {
        debugPrint('Audio warm-up failed: $e\n$st');
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
          home: const EntryScreen(),                // здесь выполняется bootstrap (Auth/Dio/Player)
          navigatorObservers: [routeObserver],
          // ⬇️ важно: тот же ключ, что и в PushService
          navigatorKey: _navKey,
        );
      },
    );
  }
}
