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
  const MainScreen({super.key});

  static _MainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1; // Каталог по умолчанию

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onPlayerTap() {
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

  void setTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // --- ИСПРАВЛЕННАЯ СТРОКА ДЛЯ ОТЛАДКИ ---
    debugPrint('[ОТЛАДКА] Текущий тип пользователя: ${context.watch<UserNotifier>().userType}');
    // ------------------------------------

    final List<Widget> pages = [
      const CatalogAndCollectionsScreen(), // index 0
      const CatalogScreen(),               // index 1
      const SizedBox.shrink(),             // index 2 (пустышка для центральной кнопки)
      const ProfileScreen(),               // index 3
    ];

    final body = pages[(_selectedIndex >= 0 && _selectedIndex < pages.length) ? _selectedIndex : 1];

    return Scaffold(
      body: body,
      bottomNavigationBar: Consumer<UserNotifier>(
        builder: (context, userNotifier, child) {
          return CustomBottomNavBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              if (index == 3) {
                if (userNotifier.isAuth) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
                return;
              }
              _onTabSelected(index);
            },
            onPlayerTap: _onPlayerTap,
          );
        },
      ),
    );
  }
}
