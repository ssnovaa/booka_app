// ПУТЬ: lib/screens/catalog_and_collections_screen.dart

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

class _CatalogAndCollectionsScreenState extends State<CatalogAndCollectionsScreen>
    with SingleTickerProviderStateMixin {
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

  // Смена вкладки MainScreen, чтобы не терять навбар
  void _goToRootCatalogScreen() {
    final mainState = MainScreen.of(context);
    mainState?.setTab(1); // 1 — индекс каталога в MainScreen!
  }

  // <<< ВАЖНО: перехват "Назад"
  Future<bool> _onWillPop() async {
    // Если сейчас открыта вкладка "Подборки" (index == 1),
    // переключаемся на "Каталог" (index == 0) и НЕ закрываем экран.
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      return false;
    }
    // Иначе позволяем всплыть назад (MainScreen уже решит, что делать дальше)
    return true;
  }
  // >>>

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop, // <-- добавлено
      child: Scaffold(
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
            const CollectionsStubScreen(),
          ],
        ),
      ),
    );
  }
}
