// lib/screens/catalo g_and_collections_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../widgets/booka_app_bar.dart';
import 'genres_screen.dart';
import 'main_screen.dart';
import '../core/network/api_client.dart';
import '../constants.dart';
import 'series_books_list_screen.dart';
import 'package:booka_app/widgets/loading_indicator.dart'; // ← Lottie-лоадер замість стандартного бублика

class CatalogAndCollectionsScreen extends StatefulWidget {
  const CatalogAndCollectionsScreen({Key? key}) : super(key: key);

  @override
  State<CatalogAndCollectionsScreen> createState() =>
      _CatalogAndCollectionsScreenState();
}

class _CatalogAndCollectionsScreenState
    extends State<CatalogAndCollectionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Централізований хук для MainScreen:
  /// якщо відкрита «Серії» → перемикаємо на «Жанри» і повертаємо true.
  bool handleBackAtRoot() {
    if (_tabController.index == 1) {
      _tabController.animateTo(0);
      return true;
    }
    return false;
  }

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

  /// «Як у профілі»: переключити нижній таб MainScreen.
  /// Якщо MainScreen недоступний (екран відкрито окремо) — відкрити MainScreen з потрібною вкладкою.
  Future<void> _switchMainTab(int tab) async {
    final ms = MainScreen.of(context);
    if (ms != null) {
      ms.setTab(tab);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainScreen(initialIndex: tab)),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.colorScheme.surface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    return Scaffold(
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
        children: [
          // Дочірній екран зможе «повернутися на головний каталог»
          GenresScreen(
            key: const PageStorageKey('genres_tab'),
            onReturnToMain: () => _switchMainTab(1),
          ),
          const _SeriesTab(key: PageStorageKey('series_tab')),
        ],
      ),
    );
  }
}

/// ==================== Вкладка «Серії» ====================

class _SeriesTab extends StatefulWidget {
  const _SeriesTab({Key? key}) : super(key: key);

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
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (r.statusCode != 200 || r.data == null) {
        return <Map<String, dynamic>>[];
      }

      final raw = (r.data is Map && (r.data as Map).containsKey('data'))
          ? (r.data['data'] as List?)
          : (r.data is List ? r.data as List : null);

      if (raw == null) return <Map<String, dynamic>>[];

      return raw
          .whereType<dynamic>()
          .map((e) => e is Map<String, dynamic>
          ? e
          : Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _refresh() async {
    final fut = _fetchSeries();
    setState(() => _future = fut);
    await fut;
  }

  String? _abs(String? url) => ensureAbsoluteImageUrl(url);

  String? _seriesCover(Map<String, dynamic> series) {
    final firstCover =
    (series['first_cover'] ?? series['firstCover'])?.toString();
    if (firstCover != null && firstCover.isNotEmpty) {
      return _abs(firstCover);
    }

    final booksRaw = series['books'];
    if (booksRaw is List && booksRaw.isNotEmpty) {
      final Map<String, dynamic> b = Map<String, dynamic>.from(booksRaw.first);
      final thumb = b['thumb_url']?.toString() ?? b['thumbUrl']?.toString();
      final cover = b['cover_url']?.toString() ?? b['coverUrl']?.toString();
      return _abs(thumb ?? cover);
    }

    final thumb =
        series['thumb_url']?.toString() ?? series['thumbUrl']?.toString();
    final cover =
        series['cover_url']?.toString() ?? series['coverUrl']?.toString();
    return _abs(thumb ?? cover);
  }

  Future<void> _openSeries(
      BuildContext context, Map<String, dynamic> series) async {
    final id = (series['id'] ?? series['series_id'])?.toString();
    final title =
    (series['title'] ?? series['name'] ?? 'Серія').toString().trim();
    if (id == null || id.isEmpty) return;

    List<Map<String, dynamic>>? prefetched;
    try {
      final r = await ApiClient.i().get(
        '/series/$id/books',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (r.statusCode == 200 && r.data is List) {
        prefetched = (r.data as List)
            .map((e) => e is Map<String, dynamic>
            ? e
            : Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeriesBooksListScreen(
          title: title.isEmpty ? 'Серія' : title,
          seriesId: id,
          initialBooks: prefetched,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;
    final placeholderBg = isDark ? Colors.white10 : Colors.black12;
    final placeholderIcon = isDark ? Colors.white54 : Colors.black45;

    Widget placeholderCard() => Container(
      decoration: BoxDecoration(
        color: placeholderBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          Icons.collections_bookmark_rounded,
          color: placeholderIcon,
          size: 30,
        ),
      ),
    );

    return RefreshIndicator.adaptive(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const _SeriesSkeleton();
          }
          final data = s.data ?? const <Map<String, dynamic>>[];

          if (data.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: t.colorScheme.surfaceVariant
                          .withOpacity(isDark ? 0.20 : 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Серій поки немає',
                      style: t.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, i) {
                      final series = data[i];
                      final title =
                      (series['title'] ?? series['name'] ?? '')
                          .toString()
                          .trim();
                      final booksCount = (series['books_count'] ??
                          series['booksCount'] ??
                          (series['books'] is List
                              ? (series['books'] as List).length
                              : 0))
                          .toString();

                      final cover = _seriesCover(series);

                      final img = ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: cover == null || cover.isEmpty
                            ? placeholderCard()
                            : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholderCard(),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            // 🔄 Lottie-індикатор під час завантаження обкладинки серії
                            return const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: LoadingIndicator(size: 22),
                              ),
                            );
                          },
                        ),
                      );

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openSeries(context, series),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: img),
                              const SizedBox(height: 6),
                              Text(
                                title.isEmpty ? 'Серія' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Книг: $booksCount',
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: t.textTheme.bodySmall?.color
                                      ?.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: data.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          );
        },
      ),
    );
  }
}

class _SeriesSkeleton extends StatelessWidget {
  const _SeriesSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base = t.colorScheme.surfaceVariant
        .withOpacity(t.brightness == Brightness.dark ? 0.24 : 0.35);

    Widget bar({double h = 12, double r = 10}) => Container(
      height: h,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(r),
      ),
    );

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, i) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  bar(h: 14, r: 6),
                  const SizedBox(height: 6),
                  bar(h: 12, r: 6),
                ],
              ),
              childCount: 6,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}
