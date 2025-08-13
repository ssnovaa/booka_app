import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/custom_bottom_nav_bar.dart';
import 'catalog_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import '../user_notifier.dart';
import 'catalog_and_collections_screen.dart';

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
    print('[MainScreen] _onTabSelected: $index');
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onPlayerTap() {
    print('[MainScreen] Player tap!');
    // TODO: Добавь логику вызова плеера
  }

  // --- Новый метод для внешней смены вкладки ---
  void setTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    print('[MainScreen] build, _selectedIndex=$_selectedIndex');
    return Consumer<UserNotifier>(
      builder: (context, userNotifier, _) {
        print('[MainScreen] Consumer<UserNotifier>: isAuth=${userNotifier.isAuth}');
        late Widget body;

        switch (_selectedIndex) {
          case 0:
            print('[MainScreen] CASE 0: ПОДБОРКИ (CatalogAndCollectionsScreen)');
            body = const CatalogAndCollectionsScreen();
            break;
          case 1:
            print('[MainScreen] CASE 1: КАТАЛОГ');
            body = const CatalogScreen();
            break;
          case 3:
            print('[MainScreen] CASE 3: ПРОФИЛЬ');
            body = const CatalogScreen(); // возможно, здесь нужен ProfileScreen
            break;
          default:
            print('[MainScreen] CASE default');
            body = const CatalogScreen();
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              print('[MainScreen] NAVBAR onTap: $index');
              if (index == 3) {
                print('[MainScreen] NAVBAR PROFILE: isAuth=${userNotifier.isAuth}');
                if (userNotifier.isAuth) {
                  print('[MainScreen] Навигация: ProfileScreen');
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                } else {
                  print('[MainScreen] Навигация: LoginScreen');
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              } else {
                _onTabSelected(index);
              }
            },
            onPlayerTap: _onPlayerTap,
          ),
        );
      },
    );
  }
}
