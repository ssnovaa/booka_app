// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/theme_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/entry_screen.dart';
import 'package:booka_app/screens/catalog_screen.dart' show routeObserver; // RouteObserver для событий навигации

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

    // 2) Сеть/кэш Dio
    try {
      await ApiClient.init();
    } catch (e, st) {
      debugPrint('ApiClient.init failed: $e\n$st');
      // fallback: ApiClient сам свалится в MemCacheStore
    }

    // 3) Провайдеры, требующие предварительной инициализации
    final themeNotifier = ThemeNotifier();
    try {
      await themeNotifier.load(); // подгрузим сохранённый режим (light/dark/system)
    } catch (e, st) {
      debugPrint('ThemeNotifier.load failed: $e\n$st');
    }

    final userNotifier = UserNotifier();
    try {
      await userNotifier.tryAutoLogin();
    } catch (e, st) {
      debugPrint('UserNotifier.tryAutoLogin failed: $e\n$st');
    }

    final audioProvider = AudioPlayerProvider();
    try {
      await audioProvider.restoreProgress();
    } catch (e, st) {
      debugPrint('AudioPlayerProvider.restoreProgress failed: $e\n$st');
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
          home: const EntryScreen(),
          navigatorObservers: [routeObserver],
        );
      },
    );
  }
}
