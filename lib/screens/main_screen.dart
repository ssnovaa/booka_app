// lib/screens/main_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemNavigator.pop
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
  /// 0 — "Каталог/Подборки", 1 — "Каталог", (2 — плеер-кнопка), 3 — Профиль (push поверх)
  int _selectedIndex = 1; // по умолчанию — Каталог

  /// Для «двойного Назад для выхода» (активно ТОЛЬКО на вкладке Каталог = 1)
  DateTime? _lastBackTap;
  final Duration _exitInterval = const Duration(seconds: 2);

  /// Вкладки, которые реально живут в IndexedStack и сохраняют своё состояние.
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
  int get _stackIndex => (_selectedIndex == 0) ? 0 : 1;

  Future<bool> _onWillPop() async {
    // Двойной выход разрешаем ТОЛЬКО на вкладке "Каталог" (index == 1).
    if (_selectedIndex != 1) {
      // На вкладке "Каталог/Подборки" работает её собственный PopScope:
      // пусть back идёт дальше (внутренний экран сам решит — переключить таб или подняться выше).
      return true;
    }

    // Мы на "Каталог": применяем двойное нажатие для выхода.
    final now = DateTime.now();
    if (_lastBackTap == null || now.difference(_lastBackTap!) > _exitInterval) {
      _lastBackTap = now;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Натисніть ще раз, щоб вийти',
              style: TextStyle(color: cs.onInverseSurface),
            ),
            backgroundColor: cs.inverseSurface,
            duration: _exitInterval,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
          ),
        );
      return false; // не выходим — ждём повторного Back
    }

    // Второе нажатие в интервале — закрываем приложение на Android.
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
      return false;
    } else {
      // На iOS программно закрывать приложение нельзя — просто игнорируем.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop, // перехватываем Back на уровне главного контейнера
      child: Consumer<UserNotifier>(
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
      ),
    );
  }
}
