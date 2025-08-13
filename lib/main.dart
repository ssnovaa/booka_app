// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/navigation/nav_service.dart';
import 'core/auth/auth_notifier.dart';
import 'core/audio/audio_background.dart';
import 'core/audio/audio_controller_v2.dart';
import 'core/network/api_client.dart';
import 'services/auth_service.dart';
import 'widgets/auth_gate.dart';
import 'widgets/mini_player.dart';

import 'features/home/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAudioBackground(); // Part 4
  runApp(const BookaApp());
}

class BookaApp extends StatelessWidget {
  const BookaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiClient()),
        ProxyProvider<ApiClient, AuthService>(
          update: (_, api, __) => AuthService(api),
        ),
        ChangeNotifierProvider(create: (ctx) => AuthNotifier(ctx.read<AuthService>())..init()),
        ChangeNotifierProvider(create: (_) => AudioControllerV2()),
      ],
      child: MaterialApp(
        navigatorKey: NavService.navigatorKey,
        title: 'Booka',
        theme: AppTheme.light(context),
        darkTheme: AppTheme.dark(context),
        themeMode: ThemeMode.system,
        home: const AuthGate(
          child: HomeShell(),
        ),
      ),
    );
  }
}
