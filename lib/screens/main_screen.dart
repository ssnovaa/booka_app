// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
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
    this.initialIndex,
  }) : super(key: key);

  final int? initialIndex;

  static _MainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;

  VoidCallback? _onContinueFromCard;

  // Єдиний основний екран каталогу (головна вкладка)
  final GlobalKey<CatalogScreenState> _catalogKey =
  GlobalKey<CatalogScreenState>();

  @override
  void initState() {
    super.initState();
    final idx = widget.initialIndex;
    if (idx == 0 || idx == 1) {
      // 0 — «Жанри/Серії» (теперь отдельный роут), 1 — головна
      // Для головного екрану просто залишаємо 1 як дефолт
      _selectedIndex = (idx == 1) ? 1 : 1;
    }
  }

  /// Открыть экран «Каталог і підбірки / Жанри / Серії» как отдельный route.
  void _openCatalogAndCollections() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CatalogAndCollectionsScreen(),
      ),
    );
  }

  void setOnContinue(VoidCallback? cb) {
    _onContinueFromCard = cb;
  }

  /// Переключение вкладок снаружи (через MainScreen.of(context)?.setTab)
  void setTab(int index) {
    if (index == 0) {
      // Раніше це був таб, тепер — окремий екран
      _openCatalogAndCollections();
    } else if (index == 1) {
      setState(() => _selectedIndex = 1);
    } else if (index == 3) {
      _onTabSelected(3);
    }
  }

  void _onTabSelected(int index) {
    // 0 — «Жанри/Серії»: теперь отдельный экран поверх MainScreen
    if (index == 0) {
      _openCatalogAndCollections();
      return;
    }

    // 1 — головна (CatalogScreen)
    if (index == 1) {
      // Повторный тап по «Домой»: если активны фильтры — сбросить их
      if (_selectedIndex == 1) {
        final st = _catalogKey.currentState;
        if (st != null && st.filtersActive) {
          st.resetFilters();
          return;
        }
      }
      setState(() => _selectedIndex = 1);
      return;
    }

    // 3 — профиль / логин
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

  Future<void> _onPlayerTap() async {
    final p = context.read<AudioPlayerProvider>();

    final ok = await p.handleBottomPlayTap();

    if (!ok) {
      _onContinueFromCard?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Основное тело теперь всегда — CatalogScreen (головна),
    // жанры/серії открываются поверх как отдельный экран.
    final Widget body = CatalogScreen(key: _catalogKey);

    return Consumer<UserNotifier>(
      builder: (context, userNotifier, _) {
        return Scaffold(
          body: body,
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: _selectedIndex,
            onTap: _onTabSelected,
            onPlayerTap: _onPlayerTap,
            onOpenPlayer: _onPlayerTap,
            onContinue: _onContinueFromCard,
          ),
        );
      },
    );
  }
}
