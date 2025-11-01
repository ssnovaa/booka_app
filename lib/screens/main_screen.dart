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

// керування плеєром напряму
import '../providers/audio_player_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    Key? key,
    this.initialIndex, // 0 — "Каталог/Підбірки", 1 — "Каталог"
  }) : super(key: key);

  /// Опціонально можна передати стартову вкладку:
  /// 0 — «Каталог/Підбірки», 1 — «Каталог».
  final int? initialIndex;

  /// Глобальний доступ до state MainScreen (наприклад, з дочірніх екранів)
  static _MainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 0 — "Каталог/Підбірки", 1 — "Каталог", (2 — кнопка плеєра), 3 — Профіль (відкривається поверх)
  int _selectedIndex = 1; // за замовчуванням — Каталог

  /// Колбек «Продовжити», спільний для картки і для центральної кнопки в навбарі.
  /// Його може встановити та частина UI, де рендериться CurrentListenCard.
  VoidCallback? _onContinueFromCard;

  /// Для «подвійного Назад для виходу» (активно ТІЛЬКИ на вкладці Каталог = 1)
  DateTime? _lastBackTap;
  final Duration _exitInterval = const Duration(seconds: 2);

  /// Ключ для доступу до стану екрану каталогу — потрібен,
  /// щоб скидати фільтри по повторному тапу на іконку «Каталог».
  final GlobalKey<CatalogScreenState> _catalogKey = GlobalKey<CatalogScreenState>();

  /// Ключ для екрану «Каталог/Підбірки», щоб ловити внутрішній Back (Серії → Жанри).
  final GlobalKey _cacKey = GlobalKey();

  /// Лінива ініціалізація вкладок: створюємо екран тільки в момент показу.
  /// Після створення — кешуємо віджет, щоб IndexedStack зберігав стан.
  final List<Widget?> _tabs = <Widget?>[null, null];

  @override
  void initState() {
    super.initState();
    // Застосовуємо initialIndex, якщо він валідний (0 або 1)
    final idx = widget.initialIndex;
    if (idx == 0 || idx == 1) {
      _selectedIndex = idx!;
    }
  }

  /// Створює і кешує вкладку i при першому запиті.
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

  // ===== ПУБЛІЧНІ МЕТОДИ ДЛЯ ДІТЕЙ ЕКРАНУ =====

  /// Встановити єдиний колбек «Продовжити» (той самий отримає і нижня центральна кнопка).
  void setOnContinue(VoidCallback? cb) {
    _onContinueFromCard = cb;
  }

  /// Публічний метод для зовнішньої зміни вкладки (наприклад, з дочірніх екранів).
  void setTab(int index) {
    if (index == 0 || index == 1) {
      setState(() => _selectedIndex = index);
    } else if (index == 3) {
      _onTabSelected(3);
    }
  }

  // ===== ВНУТРІШНЯ ЛОГІКА НАВІГАЦІЇ =====

  void _onTabSelected(int index) {
    // Індекси табів, які ми відображаємо в IndexedStack: 0 і 1.
    if (index == 0 || index == 1) {
      // Якщо вже на «Каталозі» і включені фільтри — повторний тап скидає їх.
      if (index == 1 && _selectedIndex == 1) {
        final st = _catalogKey.currentState;
        if (st != null && st.filtersActive) {
          st.resetFilters(); // ← скидаємо фільтри
          return;            // лишаємося на тій самій вкладці
        }
      }
      setState(() {
        _selectedIndex = index;
      });
      return;
    }

    // Index 3 — профіль. Відкриваємо поверх та НЕ змінюємо активну вкладку.
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

  /// Центр-кнопка: намагаємося підготувати/відновити і запустити відтворення.
  Future<void> _onPlayerTap() async {
    final p = context.read<AudioPlayerProvider>();

    // Піднімаємо збережену сесію і робимо play/pause.
    final ok = await p.handleBottomPlayTap();

    // Якщо взагалі немає збереженої сесії — викликаємо той самий «Продовжити», що у картки.
    if (!ok) {
      _onContinueFromCard?.call();
    }
  }

  /// Відображення індексу для IndexedStack.
  int get _stackIndex => (_selectedIndex == 0) ? 0 : 1;

  /// Централізований перехоплювач апаратної кнопки "Назад".
  /// Повертає false, щоб не дозволити Navigator.pop() у корені.
  Future<bool> _onWillPop() async {
    // Якщо відкрита вкладка «Каталог/Підбірки» (нижній таб 0)
    if (_selectedIndex == 0) {
      // Дамо екрану шанс «з'їсти» Back (Серії -> Жанри), якщо він вміє.
      final st = _cacKey.currentState;
      final handled = (st as dynamic?)?.handleBackAtRoot?.call() == true;
      if (handled) return false;

      // Інакше ми вже на «Жанрах»: просто переключимо нижній таб на «Каталог»
      setState(() => _selectedIndex = 1);
      return false;
    }

    // Логіка «подвійний Назад — вийти» ТІЛЬКИ на табі Каталог (1)
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
      return false; // чекаємо другого натискання
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
    // Гарантуємо, що видима вкладка створена (інша — тільки при зверненні).
    final Widget tab0 =
    (_stackIndex == 0) ? _ensureTab(0) : (_tabs[0] ?? const SizedBox.shrink());
    final Widget tab1 =
    (_stackIndex == 1) ? _ensureTab(1) : (_tabs[1] ?? const SizedBox.shrink());

    return WillPopScope(
      onWillPop: _onWillPop, // перехоплюємо Back на рівні головного контейнера
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
              onPlayerTap: _onPlayerTap,   // коротке натискання по центру
              onOpenPlayer: _onPlayerTap,  // якщо в виджеті є окремий колбек — туди ж
              onContinue: _onContinueFromCard,
            ),
          );
        },
      ),
    );
  }
}

