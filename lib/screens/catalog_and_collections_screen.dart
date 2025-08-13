import 'package:flutter/material.dart';
import '../widgets/booka_app_bar_title.dart';
import 'genres_screen.dart';
import 'collections_stub_screen.dart';
import 'main_screen.dart'; // Импортируем для доступа к MainScreen.of(context)

class CatalogAndCollectionsScreen extends StatefulWidget {
  const CatalogAndCollectionsScreen({Key? key}) : super(key: key);

  @override
  State<CatalogAndCollectionsScreen> createState() => _CatalogAndCollectionsScreenState();
}

class _CatalogAndCollectionsScreenState extends State<CatalogAndCollectionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  void _goToMainTab() {
    _tabController.animateTo(0);
  }

  // --- Новый способ: смена вкладки MainScreen, чтобы не терять навбар ---
  void _goToRootCatalogScreen() {
    final mainState = MainScreen.of(context);
    mainState?.setTab(1); // 1 — индекс каталога в MainScreen!
  }
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BookaAppBarTitle(),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
            onPressed: () {
              // TODO: переход к экрану настроек
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
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
            onReturnToMain: _goToRootCatalogScreen, // теперь только смена вкладки!
          ),
          CollectionsStubScreen(),
        ],
      ),
    );
  }
}
