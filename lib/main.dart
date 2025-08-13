import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'user_notifier.dart';
import 'providers/audio_player_provider.dart';
import 'theme_notifier.dart';
import 'screens/entry_screen.dart';
import 'models/user.dart'; // Нужен для UserType в ProxyProvider

// Глобальный RouteObserver для отслеживания навигации
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  // 1. Убеждаемся, что Flutter инициализирован
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Инициализируем фоновый аудио-сервис
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
    androidNotificationChannelName: 'Booka Audio',
    androidNotificationOngoing: true,
  );

  // 3. Запускаем приложение с провайдерами
  runApp(
    MultiProvider(
      providers: [
        // Провайдер темы (не зависит от других)
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),

        // Провайдер пользователя (не зависит от других)
        ChangeNotifierProvider(create: (_) => UserNotifier()),

        // Прокси-провайдер для аудио.
        // Он "слушает" UserNotifier и обновляет AudioPlayerProvider, когда пользователь меняется.
        ChangeNotifierProxyProvider<UserNotifier, AudioPlayerProvider>(
          // Создаем первоначальный экземпляр AudioPlayerProvider
          create: (_) => AudioPlayerProvider(),
          // Обновляем AudioPlayerProvider, передавая ему данные из UserNotifier
          update: (_, userNotifier, audioProvider) {
            // audioProvider не может быть null, так как мы его создаем выше
            audioProvider!.updateUserType(userNotifier.userType);
            return audioProvider;
          },
        ),
      ],
      child: const BookaApp(),
    ),
  );
}

class BookaApp extends StatelessWidget {
  const BookaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Используем Consumer, чтобы приложение перестраивалось при смене темы
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
          navigatorObservers: [routeObserver],
        );
      },
    );
  }
}
