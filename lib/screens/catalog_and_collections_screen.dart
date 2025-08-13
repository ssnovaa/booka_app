import 'package:flutter/material.dart';
import '../widgets/booka_app_bar_title.dart';
import 'genres_screen.dart';
import 'collections_stub_screen.dart';
import 'main_screen.dart'; // Для доступа к MainScreen.of(context)

class CatalogAndCollectionsScreen extends StatefulWidget {
  const CatalogAndCollectionsScreen({super.key});

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

  // Метод для смены вкладки на главном экране (MainScreen)
  void _goToRootCatalogScreen() {
    // Используем of(context) для вызова метода родительского стейта
    MainScreen.of(context)?.setTab(1); // 1 — это индекс каталога в MainScreen
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        // Используем кастомный виджет для заголовка
        title: const BookaAppBarTitle(),
        centerTitle: false,
        // Цвета и стили берутся из темы для консистентности
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        elevation: theme.appBarTheme.elevation ?? 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: () {
              // TODO: реализовать переход к экрану настроек
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // Вкладки теперь const
          tabs: const [
            Tab(text: 'Каталог'),
            Tab(text: 'Подборки'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        // Дочерние экраны теперь const для лучшей производительности
        children: [
          GenresScreen(
            onReturnToMain: _goToRootCatalogScreen,
          ),
          const CollectionsStubScreen(),
        ],
      ),
    );
  }
}
