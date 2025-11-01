// lib/screens/catalog_and_collections_screen.dart
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

  // 🔑 ключ к внутреннему GenresScreen (тип не указываем, он приватный в другом файле)
  final GlobalKey _genresKey = GlobalKey(debugLabel: 'GenresScreenKey');

  /// Централізований хук для MainScreen:
  /// якщо відкрита «Серії» → перемикаємо на «Жанри» і повертаємо true.
  /// якщо відкрита «Жанри» і є активний жанр → скидаємо вибір і повертаємо true.
  bool handleBackAtRoot() {
    if (_tabController.index == 1) {
      _tabController.animateTo(0);
      return true;
    }

    if (_tabController.index == 0) {
      final st = _genresKey.currentState;
      if (st != null) {
        try {
          final handled = (st as dynamic).handleBackSync?.call(scrollToTop: true) as bool?;
          if (handled == true) return true;
        } catch (_) {}
      }
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

  Future<bool> _onWillPop() async {
    if (handleBackAtRoot()) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.colorScheme.surface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    return WillPopScope(
      onWillPop: _onWillPop,
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
          children: [
            KeyedSubtree(
              key: const PageStorageKey('genres_tab'),
              child: GenresScreen(
                key: _genresKey,
                onReturnToMain: () => _switchMainTab(1),
              ),
            ),
            const _SeriesTab(key: PageStorageKey('series_tab')),
          ],
        ),
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
          .map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))
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
    final firstCover = (series['first_cover'] ?? series['firstCover'])?.toString();
    if (firstCover != null && firstCover.isNotEmpty) return _abs(firstCover);

    final booksRaw = series['books'];
    if (booksRaw is List && booksRaw.isNotEmpty) {
      final Map<String, dynamic> b = Map<String, dynamic>.from(booksRaw.first);
      final thumb = b['thumb_url']?.toString() ?? b['thumbUrl']?.toString();
      final cover = b['cover_url']?.toString() ?? b['coverUrl']?.toString();
      return _abs(thumb ?? cover);
    }

    final thumb = series['thumb_url']?.toString() ?? series['thumbUrl']?.toString();
    final cover = series['cover_url']?.toString() ?? series['coverUrl']?.toString();
    return _abs(thumb ?? cover);
  }

  String _seriesTitle(Map<String, dynamic> series) {
    return (series['title'] ?? series['name'] ?? 'Серія').toString().trim();
  }

  String? _seriesDescription(Map<String, dynamic> series) {
    final d = (series['description'] ?? series['desc'])?.toString().trim();
    if (d == null || d.isEmpty) return null;
    return d;
  }

  String _seriesBooksCount(Map<String, dynamic> series) {
    final n = (series['books_count'] ??
        series['booksCount'] ??
        (series['books'] is List ? (series['books'] as List).length : 0));
    return n.toString();
  }

  Future<void> _openSeries(BuildContext context, Map<String, dynamic> series) async {
    final id = (series['id'] ?? series['series_id'])?.toString();
    final title = _seriesTitle(series);
    if (id == null || id.isEmpty) return;

    List<Map<String, dynamic>>? prefetched;
    try {
      final r = await ApiClient.i().get(
        '/series/$id/books',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (r.statusCode == 200 && r.data is List) {
        prefetched = (r.data as List)
            .map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))
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

    Widget placeholderCover(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: placeholderBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Icon(
          Icons.collections_bookmark_rounded,
          color: placeholderIcon,
          size: 28,
        ),
      ),
    );

    return RefreshIndicator.adaptive(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const _SeriesSkeletonList();
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
                      color: t.colorScheme.surfaceVariant.withOpacity(isDark ? 0.20 : 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Серій поки немає',
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            );
          }

          // 👉 Одна серия = одна строка
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                sliver: SliverList.separated(
                  itemCount: data.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final series = data[i];
                    final title = _seriesTitle(series);
                    final desc = _seriesDescription(series);
                    final booksCount = _seriesBooksCount(series);
                    final coverUrl = _seriesCover(series);

                    return _SeriesRowCard(
                      title: title.isEmpty ? 'Серія' : title,
                      description: desc,
                      booksCount: booksCount,
                      coverUrl: coverUrl,
                      onTap: () => _openSeries(context, series),
                      placeholderBuilder: (w, h) => placeholderCover(w, h),
                    );
                  },
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

/// Адаптивный расчёт размера обложки
Size _adaptiveCoverSize(double screenW) {
  // База: 123×184 (увеличено на треть от 92×138)
  const baseW = 123.0;
  const baseH = 184.0;

  double factor;
  if (screenW >= 900) {
    factor = 1.5;   // большие планшеты/десктоп
  } else if (screenW >= 720) {
    factor = 1.35;  // планшеты 8–10"
  } else if (screenW >= 600) {
    factor = 1.25;  // большие телефоны / маленькие планшеты
  } else if (screenW >= 480) {
    factor = 1.15;  // широкие телефоны
  } else if (screenW >= 360) {
    factor = 1.0;   // типичные телефоны
  } else {
    factor = 0.92;  // сверхузкие (малые) устройства
  }

  return Size(baseW * factor, baseH * factor);
}

/// Карточка серии в одну строку: слева обложка, справа контент
class _SeriesRowCard extends StatelessWidget {
  final String title;
  final String? description;
  final String booksCount;
  final String? coverUrl;
  final VoidCallback? onTap;
  final Widget Function(double w, double h) placeholderBuilder;

  const _SeriesRowCard({
    Key? key,
    required this.title,
    required this.description,
    required this.booksCount,
    required this.coverUrl,
    required this.onTap,
    required this.placeholderBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final screenW = MediaQuery.of(context).size.width;
    final coverSize = _adaptiveCoverSize(screenW);
    final coverW = coverSize.width;
    final coverH = coverSize.height;

    return Material(
      color: t.colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Обложка слева (адаптивные размеры)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: coverW,
                  height: coverH,
                  child: (coverUrl == null || coverUrl!.isEmpty)
                      ? placeholderBuilder(coverW, coverH)
                      : Image.network(
                    coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholderBuilder(coverW, coverH),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: LoadingIndicator(size: 22),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Контент справа
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Заголовок: 2 строки + тултип
                    Tooltip(
                      message: title,
                      waitDuration: const Duration(milliseconds: 300),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),

                    // Описание (если есть): до 2 строк
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: t.colorScheme.onSurface.withOpacity(0.85),
                          height: 1.28,
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Книг в серии
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.colorScheme.primary.withOpacity(
                          Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: t.colorScheme.primary.withOpacity(
                            Theme.of(context).brightness == Brightness.dark ? 0.40 : 0.25,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.library_books_rounded, size: 16, color: t.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Книг в серії: $booksCount',
                            style: t.textTheme.labelLarge?.copyWith(
                              color: t.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Скелетон для списка серий (одна строка = одна серия)
class _SeriesSkeletonList extends StatelessWidget {
  const _SeriesSkeletonList();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base =
    t.colorScheme.surfaceVariant.withOpacity(t.brightness == Brightness.dark ? 0.24 : 0.35);

    final screenW = MediaQuery.of(context).size.width;
    final coverSize = _adaptiveCoverSize(screenW);

    Widget block({double w = 100, double h = 16, double r = 8}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(r)),
    );

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverList.separated(
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              return Material(
                color: t.colorScheme.surface,
                elevation: 1,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Обложка-скелет (адаптивные размеры)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: coverSize.width,
                          height: coverSize.height,
                          color: base,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // текст-скелет
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            block(w: 220, h: 18, r: 6),
                            const SizedBox(height: 8),
                            block(w: 180, h: 14, r: 6),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                block(w: 130, h: 26, r: 999),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}
