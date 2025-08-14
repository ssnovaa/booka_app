// lib/screens/main_screen.dart
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

  /// Глобальный доступ к state MainScreen (например, из дочерних экранов)
  static _MainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Индекс текущей вкладки в навбаре.
  /// 0 — Подборки, 1 — Каталог, (2 — кнопка плеера через onPlayerTap), 3 — Профиль (пушится поверх).
  int _selectedIndex = 1; // по умолчанию — Каталог

  /// Вкладки, которые реально живут в IndexedStack и сохраняют своё состояние.
  /// Профиль сюда не входит, т.к. открывается отдельным экраном (push).
  late final List<Widget> _tabs = const <Widget>[
    CatalogAndCollectionsScreen(),
    CatalogScreen(),
  ];

  void _onTabSelected(int index) {
    // Индексы табов, которые мы отображаем в IndexedStack: 0 и 1.
    if (index == 0 || index == 1) {
      setState(() {
        _selectedIndex = index;
      });
      return;
    }

    // Index 3 — профиль. Открываем поверх и НЕ меняем активную вкладку.
    if (index == 3) {
      final userNotifier = Provider.of<UserNotifier>(context, listen: false);
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

    // Прочие индексы (например, центр-плеер) обрабатываются через onPlayerTap в навбаре.
  }

  void _onPlayerTap() {
    // TODO: логика открытия мини-плеера/полного плеера
    debugPrint('[MainScreen] Player tap!');
  }

  /// Публичный метод для внешней смены вкладки (например, из дочерних экранов).
  void setTab(int index) {
    if (index == 0 || index == 1) {
      setState(() => _selectedIndex = index);
    } else if (index == 3) {
      _onTabSelected(3);
    }
  }

  /// Маппинг индекса нижней навигации в индекс IndexedStack.
  /// У нас в стеке только 0 и 1.
  int get _stackIndex => (_selectedIndex == 0) ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    return Consumer<UserNotifier>(
      builder: (context, userNotifier, _) {
        return Scaffold(
          body: IndexedStack(
            index: _stackIndex,
            children: _tabs,
          ),
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: _selectedIndex,
            onTap: _onTabSelected,
            onPlayerTap: _onPlayerTap,
          ),
        );
      },
    );
  }
}
