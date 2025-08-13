import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/custom_bottom_nav_bar.dart';
import 'catalog_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import '../user_notifier.dart';
import 'catalog_and_collections_screen.dart';
import '../player/bottom_sheet_player.dart';
import '../providers/audio_player_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  // --- Даем глобальный доступ к state MainScreen ---
  static _MainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1; // Каталог по умолчанию

  void _onTabSelected(int index) {
    debugPrint('[MainScreen] _onTabSelected: $index');
    setState(() {
      _selectedIndex = index;
    });
  }

  // Кнопка плеера из минибара — открыть всплывающий плеер
  void _onPlayerTap() {
    debugPrint('[MainScreen] Player tap!');
    final audio = context.read<AudioPlayerProvider>();

    final hasCurrent = audio.currentBook != null && audio.currentChapter != null;
    if (hasCurrent) {
      BottomSheetPlayer.show(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сейчас ничего не воспроизводится')),
      );
    }
  }

  // --- Новый метод для внешней смены вкладки ---
  void setTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[MainScreen] build, _selectedIndex=$_selectedIndex');
    return Consumer<UserNotifier>(
      builder: (context, userNotifier, _) {
        debugPrint('[MainScreen] Consumer<UserNotifier>: isAuth=${userNotifier.isAuth}');
        late Widget body;

        switch (_selectedIndex) {
          case 0:
            debugPrint('[MainScreen] CASE 0: ПОДБОРКИ (CatalogAndCollectionsScreen)');
            body = const CatalogAndCollectionsScreen();
            break;
          case 1:
            debugPrint('[MainScreen] CASE 1: КАТАЛОГ');
            body = const CatalogScreen();
            break;
          case 3:
            debugPrint('[MainScreen] CASE 3: ПРОФИЛЬ');
            body = const ProfileScreen(); // ← ставим реальный профиль
            break;
          default:
            debugPrint('[MainScreen] CASE default');
            body = const CatalogScreen();
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              debugPrint('[MainScreen] NAVBAR onTap: $index');

              // Профиль открываем как отдельный экран (как у тебя и было)
              if (index == 3) {
                debugPrint('[MainScreen] NAVBAR PROFILE: isAuth=${userNotifier.isAuth}');
                if (userNotifier.isAuth) {
                  debugPrint('[MainScreen] Навигация: ProfileScreen (push)');
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                } else {
                  debugPrint('[MainScreen] Навигация: LoginScreen (push)');
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
                return;
              }

              _onTabSelected(index);
            },
            onPlayerTap: _onPlayerTap,
          ),
        );
      },
    );
  }
}
