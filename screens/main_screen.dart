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

  final GlobalKey<CatalogScreenState> _catalogKey =
  GlobalKey<CatalogScreenState>();

  final GlobalKey _cacKey = GlobalKey();

  final List<Widget?> _tabs = <Widget?>[null, null];

  @override
  void initState() {
    super.initState();
    final idx = widget.initialIndex;
    if (idx == 0 || idx == 1) {
      _selectedIndex = idx!;
    }
  }

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

  void setOnContinue(VoidCallback? cb) {
    _onContinueFromCard = cb;
  }

  void setTab(int index) {
    if (index == 0 || index == 1) {
      setState(() => _selectedIndex = index);
    } else if (index == 3) {
      _onTabSelected(3);
    }
  }

  void _onTabSelected(int index) {
    if (index == 0 || index == 1) {
      if (index == 1 && _selectedIndex == 1) {
        final st = _catalogKey.currentState;
        if (st != null && st.filtersActive) {
          st.resetFilters();
          return;
        }
      }
      setState(() => _selectedIndex = index);
      return;
    }

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

  int get _stackIndex => (_selectedIndex == 0) ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    final Widget tab0 =
    (_stackIndex == 0) ? _ensureTab(0) : (_tabs[0] ?? const SizedBox());
    final Widget tab1 =
    (_stackIndex == 1) ? _ensureTab(1) : (_tabs[1] ?? const SizedBox());

    return Consumer<UserNotifier>(
      builder: (context, userNotifier, _) {
        return Scaffold(
          body: IndexedStack(
            index: _stackIndex,
            children: <Widget>[tab0, tab1],
          ),
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
