import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_notifier.dart';
import 'providers/audio_player_provider.dart';
import 'theme_notifier.dart';
import 'screens/entry_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';

// --- Глобальный RouteObserver, ОБЯЗАТЕЛЬНО --- //
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация just_audio_background для уведомлений и локскрина
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
    androidNotificationChannelName: 'Booka Audio',
    androidNotificationOngoing: true,
  );

  // --- Автоматическое восстановление прогресса при старте ---
  final audioProvider = AudioPlayerProvider();
  await audioProvider.restoreProgress();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider(create: (_) => UserNotifier()),
        ChangeNotifierProvider(create: (_) => audioProvider), // передаем уже инициализированный!
      ],
      child: const BookaApp(),
    ),
  );
}

class BookaApp extends StatelessWidget {
  const BookaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, _) {
        return MaterialApp(
          title: 'Booka',
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: Colors.deepPurple,
            scaffoldBackgroundColor: Colors.white,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.deepPurple,
            scaffoldBackgroundColor: Colors.black,
          ),
          themeMode: themeNotifier.themeMode,
          home: const EntryScreen(),
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver], // --- обязательно!
        );
      },
    );
  }
}
