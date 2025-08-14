// ПУТЬ: lib/screens/catalog_and_collections_screen.dart

import 'package:flutter/material.dart';
import '../widgets/booka_app_bar.dart'; // общий AppBar с глобальной кнопкой темы
import 'genres_screen.dart';
import 'collections_stub_screen.dart';
import 'main_screen.dart'; // для MainScreen.of(context)

class CatalogAndCollectionsScreen extends StatefulWidget {
  const CatalogAndCollectionsScreen({Key? key}) : super(key: key);

  @override
  State<CatalogAndCollectionsScreen> createState() => _CatalogAndCollectionsScreenState();
}

class _CatalogAndCollectionsScreenState extends State<CatalogAndCollectionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Если нужно из дочерних экранов прыгать на корень каталога
  void _goToRootCatalogScreen() {
    final mainState = MainScreen.of(context);
    mainState?.setTab(1); // 1 — индекс каталога в MainScreen
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.colorScheme.surface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    return PopScope(
      canPop: false, // сами решаем, когда всплывать наверх
      onPopInvoked: (didPop) {
        if (didPop) return;

        // Если сейчас "Подборки" — переключаем на "Каталог" и не выходим
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
          return;
        }

        // Уже "Каталог" — отдадим pop наверх (вернёт на предыдущий экран/закроет приложение)
        Navigator.of(context).maybePop();
      },
      child: Scaffold(
        appBar: bookaAppBar(
          backgroundColor: appBarBg,
          // ⚠️ Никаких дополнительных actions — шестерёнки больше не будет.
          actions: const [],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: primary,
            labelColor: primary,
            unselectedLabelColor: onSurfaceVariant,
            tabs: const [
              Tab(text: 'Каталог'),
              Tab(text: 'Подборки'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            GenresScreen(
              key: const PageStorageKey('genres_tab'),
              onReturnToMain: _goToRootCatalogScreen,
            ),
            const CollectionsStubScreen(
              key: PageStorageKey('collections_tab'),
            ),
          ],
        ),
      ),
    );
  }
}
