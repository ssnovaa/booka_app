// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/theme_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/entry_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.booka.audioplayer.channel.audio',
    androidNotificationChannelName: 'Booka Audio',
    androidNotificationOngoing: true,
  );

  await ApiClient.init();

  final audioProvider = AudioPlayerProvider();
  await audioProvider.restoreProgress();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider(create: (_) => UserNotifier()),
        ChangeNotifierProvider.value(value: audioProvider),
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
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeNotifier.themeMode,
          home: const EntryScreen(),
        );
      },
    );
  }
}
