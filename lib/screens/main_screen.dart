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

// управление плеером напрямую
import '../providers/audio_player_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    Key? key,
    this.initialIndex, // 0 — "Каталог/Подборки", 1 — "Каталог"
  }) : super(key: key);

  /// Опционально можно передать стартовую вкладку:
  /// 0 — «Каталог/Подборки», 1 — «Каталог».
  final int? initialIndex;

  /// Глобальный доступ к state MainScreen (например, из дочерних экранов)
  static _MainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 0 — "Каталог/Подборки", 1 — "Каталог", (2 — плеер-кнопка), 3 — Профіль (push поверх)
  int _selectedIndex = 1; // по умолчанию — Каталог

  /// Колбэк «Продовжити», общий для карточки и для центральной кнопки в навбаре.
  /// Его может установить та часть UI, где рендерится CurrentListenCard.
  VoidCallback? _onContinueFromCard;

  /// Для «двойного Назад для выхода» (активно ТОЛЬКО на вкладке Каталог = 1)
  DateTime? _lastBackTap;
  final Duration _exitInterval = const Duration(seconds: 2);

  /// Ключ для доступа к состоянию экрана каталога — нужен,
  /// чтобы сбрасывать фильтры по повторному тапу на иконку «Каталог».
  final GlobalKey<CatalogScreenState> _catalogKey = GlobalKey<CatalogScreenState>();

  /// Ключ для экрана «Каталог/Подборки», чтобы ловить внутренний Back (Серії → Жанри).
  final GlobalKey _cacKey = GlobalKey();

  /// Ленивая инициализация вкладок: создаём экран только в момент показа.
  /// После создания — кешируем виджет, чтобы IndexedStack сохранял состояние.
  final List<Widget?> _tabs = <Widget?>[null, null];

  @override
  void initState() {
    super.initState();
    // Применяем initialIndex, если он валиден (0 или 1)
    final idx = widget.initialIndex;
    if (idx == 0 || idx == 1) {
      _selectedIndex = idx!;
    }
  }

  /// Создаёт и кеширует вкладку i при первом запросе.
  Widget _ensureTab(int i) {
    if (_tabs[i] != null) return _tabs[i]!;
    switch (i) {
      case 0:
        _tabs[0] = CatalogAndCollectionsScreen(key: _cacKey);
        break;
      case 1:
        _tabs[1] = CatalogScreen(key: _catalogKey);
        break;
    }
    return _tabs[i]!;
  }

  // ===== ПУБЛИЧНЫЕ МЕТОДЫ ДЛЯ ДЕТЕЙ ЭКРАНА =====

  /// Установить единый колбэк «Продовжити» (его же получит и нижняя центральная кнопка).
  void setOnContinue(VoidCallback? cb) {
    _onContinueFromCard = cb;
  }

  /// Публичный метод для внешней смены вкладки (например, из дочерних экранов).
  void setTab(int index) {
    if (index == 0 || index == 1) {
      setState(() => _selectedIndex = index);
    } else if (index == 3) {
      _onTabSelected(3);
    }
  }

  // ===== ВНУТРЕННЯЯ ЛОГИКА НАВИГАЦИИ =====

  void _onTabSelected(int index) {
    // Индексы табов, которые мы отображаем в IndexedStack: 0 и 1.
    if (index == 0 || index == 1) {
      // Если уже на «Каталоге» и включены фильтры — повторный тап сбрасывает их.
      if (index == 1 && _selectedIndex == 1) {
        final st = _catalogKey.currentState;
        if (st != null && st.filtersActive) {
          st.resetFilters(); // ← сброс фильтров
          return;            // остаёмся на той же вкладке
        }
      }
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
  }

  /// Центр-кнопка: пытаемся подготовить/восстановить и запустить воспроизведение.
  Future<void> _onPlayerTap() async {
    final p = context.read<AudioPlayerProvider>();

    // Пытаемся поднять сохранённую сессию и сделать play/pause.
    final ok = await p.handleBottomPlayTap();

    // Если вообще нет сохранённой сессии — дёргаем тот же «Продовжити», что у карточки.
    if (!ok) {
      _onContinueFromCard?.call();
    }
  }

  /// Маппинг индекса нижней навигации в индекс IndexedStack.
  int get _stackIndex => (_selectedIndex == 0) ? 0 : 1;

  /// Централизованный перехват аппаратной «Назад».
  /// Возвращает false, чтобы не пускать Navigator.pop() у корня.
  Future<bool> _onWillPop() async {
    // Если открыта вкладка «Каталог/Подборки» (нижний таб 0)
    if (_selectedIndex == 0) {
      // Дадим экрану шанс «съесть» Back (Серії -> Жанри), если он это умеет.
      final st = _cacKey.currentState;
      final handled = (st as dynamic?)?.handleBackAtRoot?.call() == true;
      if (handled) return false;

      // Иначе мы уже на «Жанри»: просто переключим нижний таб на «Каталог»
      setState(() => _selectedIndex = 1);
      return false;
    }

    // Ниже — логика «двойной Назад — выйти» ТОЛЬКО на табе Каталог (1)
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
      return false; // ждём второй Back
    }

    if (Platform.isAndroid) {
      await SystemNavigator.pop();
      return false;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Гарантируем, что видимая вкладка создана (вторая — только при обращении).
    final Widget tab0 =
    (_stackIndex == 0) ? _ensureTab(0) : (_tabs[0] ?? const SizedBox.shrink());
    final Widget tab1 =
    (_stackIndex == 1) ? _ensureTab(1) : (_tabs[1] ?? const SizedBox.shrink());

    return WillPopScope(
      onWillPop: _onWillPop, // перехватываем Back на уровне главного контейнера
      child: Consumer<UserNotifier>(
        builder: (context, userNotifier, _) {
          return Scaffold(
            body: IndexedStack(
              index: _stackIndex,
              children: <Widget>[tab0, tab1],
            ),
            bottomNavigationBar: CustomBottomNavBar(
              currentIndex: _selectedIndex,
              onTap: _onTabSelected,
              onPlayerTap: _onPlayerTap,   // короткое нажатие по центру
              onOpenPlayer: _onPlayerTap,  // если в виджете есть отдельный колбэк — туда же
              onContinue: _onContinueFromCard,
            ),
          );
        },
      ),
    );
  }
}
