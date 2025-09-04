// ШЛЯХ: lib/screens/catalog_and_collections_screen.dart

import 'package:flutter/material.dart';
import '../widgets/booka_app_bar.dart';
import 'genres_screen.dart';
import 'main_screen.dart';
import 'series_books_list_screen.dart';
import '../core/network/api_client.dart';

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

  /// Універсальний обробник «Назад» для цього екрана.
  /// Повертає true, якщо подію оброблено тут (Navigator не чіпаємо).
  bool _handleBackHere() {
    debugPrint('[BACK][CAC] tapped. tabIndex=${_tabController.index}');

    // Якщо ми на «Серії» (index == 1) — повернутися на «Жанри» (index == 0)
    if (_tabController.index == 1) {
      _tabController.animateTo(0);
      debugPrint('[BACK][CAC] Switched Series -> Genres');
      _showHint('Повернення: Серії → Жанри');
      return true;
    }

    // Ми на «Жанри»: попросимо MainScreen переключитися на таб каталогу (index 1)
    final main = MainScreen.of(context);
    if (main != null) {
      main.setTab(1);
      debugPrint('[BACK][CAC] Asked MainScreen.setTab(1) (go to Catalog tab)');
      _showHint('На головний каталог');
      return true;
    }

    // Якщо MainScreen не знайдено (не повинно бути у звичайному потоці),
    // повернемо false, щоб вирішити далі на рівні навігатора.
    debugPrint('[BACK][CAC] MainScreen.of(context) == null (not handled here)');
    return false;
  }

  void _showHint(String msg) {
    // короткий snackbar, щоб було видно «куди повело»
    final sm = ScaffoldMessenger.maybeOf(context);
    if (sm != null) {
      sm.hideCurrentSnackBar();
      sm.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.colorScheme.surface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    // BackButtonListener викликається раніше ніж Navigator.pop().
    // Якщо повернемо true — подію «з'їдено», застосунок не закриється.
    return BackButtonListener(
      onBackButtonPressed: () {
        final handled = _handleBackHere();
        return handled;
      },
      child: Scaffold(
        appBar: bookaAppBar(
          backgroundColor: appBarBg,
          actions: const [],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: primary,
            labelColor: primary,
            unselectedLabelColor: onSurfaceVariant,
            tabs: const [
              Tab(text: 'Жанри'),
              Tab(text: 'Серії'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: const [
            GenresScreen(key: PageStorageKey('genres_tab')),
            _SeriesTab(key: PageStorageKey('series_tab')),
          ],
        ),
      ),
    );
  }
}

class _SeriesTab extends StatefulWidget {
  const _SeriesTab({super.key});

  @override
  State<_SeriesTab> createState() => _SeriesTabState();
}

class _SeriesTabState extends State<_SeriesTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchSeries();
  }

  Future<List<Map<String, dynamic>>> _fetchSeries() async {
    try {
      final r = await ApiClient.i().get(
        '/series',
        // Дозволяємо будь-яку статус-код <=499 для подальшої обробки (але фільтруємо нижче).
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (r == null || r.statusCode != 200 || r.data == null) {
        return <Map<String, dynamic>>[];
      }

      // API може повертати { data: [...] } або просто [...] — обробляємо обидва випадки.
      final dynamic raw = (r.data is Map && (r.data as Map).containsKey('data'))
          ? (r.data['data'] as List<dynamic>?)
          : (r.data as List<dynamic>?);

      final list = (raw ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      return list;
    } catch (e, st) {
      debugPrint('[SeriesTab] fetch error: $e\n$st');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data ?? const <Map<String, dynamic>>[];

        if (snap.connectionState == ConnectionState.waiting) {
          return _loadingSkeleton(context);
        }

        if (data.isEmpty) {
          return const Center(
            child: Text('Серії поки що відсутні'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final item = data[i];
            final id = item['id'] is int ? item['id'] as int : (int.tryParse('${item['id']}'));
            final title = (item['title'] as String?)?.trim();

            if (id == null || (title == null || title.isEmpty)) {
              return const SizedBox.shrink();
            }

            return ListTile(
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SeriesBooksListScreen(
                      seriesId: id,
                      title: title,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _loadingSkeleton(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHigh;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 56,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
