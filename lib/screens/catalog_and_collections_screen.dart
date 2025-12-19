// lib/screens/catalog_and_collections_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../widgets/booka_app_bar.dart';
import 'genres_screen.dart';
import '../core/network/api_client.dart';
import '../constants.dart';
import 'series_books_list_screen.dart';
import 'package:booka_app/widgets/loading_indicator.dart';
import '../core/network/image_cache.dart';

// 🔥 IMPORT NEW SERVICE
import '../services/catalog_service.dart';

// Player
import '../providers/audio_player_provider.dart';
import '../user_notifier.dart';
import '../models/user.dart'; // getUserType

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
  VoidCallback? _onContinueFromCard;

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

  // --- Действие при нажатии на кнопку ---
  Future<void> _onFabTap() async {
    final p = context.read<AudioPlayerProvider>();
    final userN = context.read<UserNotifier>();

    // 1) Актуализируем тип пользователя
    p.userType = getUserType(userN.user);

    // 2) Привязываем consumer
    await p.ensureCreditsTickerBound();

    // 3) Пытаемся продолжить
    final bool started = await p.handleBottomPlayTap();

    if (!started) {
      _onContinueFromCard?.call();
      return;
    }

    p.rearmFreeSecondsTickerSafely();

    Future.microtask(() => p.ensureCreditsTickerBound());
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        p.ensureCreditsTickerBound();
        p.rearmFreeSecondsTickerSafely();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.colorScheme.surface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    return PopScope(
      canPop: false, // сами решаем, когда делать pop
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // 1) Если сейчас вкладка «Серії» — просто переключаемся на «Жанри»
        if (_tabController.index == 1) {
          _tabController.animateTo(0);
          return;
        }

        // 2) Если вкладка «Жанри» — пытаемся сбросить выбранный жанр
        final state = _genresKey.currentState;
        if (state != null) {
          try {
            // _GenresScreenState має метод handleBackSync({bool scrollToTop = true})
            final dynamic dyn = state;
            final bool handled = dyn.handleBackSync(scrollToTop: true);
            if (handled) {
              // жанр був обраний — повернулися до сітки жанрів, pop не робимо
              return;
            }
          } catch (_) {
            // если метода нет — игнорируем
          }
        }

        // 3) Жоден жанр не обраний, вкладка вже «Жанри» → просто закриваємо екран
        // і повертаємось на MainScreen
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
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
          children: [
            KeyedSubtree(
              key: const PageStorageKey('genres_tab'),
              child: GenresScreen(
                key: _genresKey,
                // Тепер «повернутись на головну» для жанрів = просто закрити цей роут
                onReturnToMain: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            const _SeriesTab(key: PageStorageKey('series_tab')),
          ],
        ),
        // 🔥 КНОПКА СПРАВА ВНИЗУ (ПОД ПАЛЕЦ)
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: Consumer<AudioPlayerProvider>(
          builder: (context, audio, _) {
            final isPlaying = audio.isPlaying;
            final isDark = theme.brightness == Brightness.dark;
            final screenBg = theme.scaffoldBackgroundColor;

            // Цвета как в CustomBottomNavBar
            // Внутренний фон: светлая тема = primary(0.8), темная = screenBg
            final Color fabInnerColor = isDark
                ? screenBg
                : theme.colorScheme.primary.withOpacity(0.8);

            const Color ringBlue = Color(0xFF2196F3);     // Синий ободок
            const Color iconYellow = Color(0xFFfffc00);   // Желтая иконка

            // Размеры
            const double size = 78.0;

            return Padding(
              // 🔥 ОТОДВИГАЕМ КНОПКУ ЛЕВЕЕ ОТ КРАЯ
              padding: const EdgeInsets.only(right: 26.0),
              child: SizedBox(
                width: size,
                height: size,
                // Используем нашу кастомную "нарядную" кнопку
                child: _FancySpinningFab(
                  onTap: _onFabTap,
                  isPlaying: isPlaying,
                  bgColor: fabInnerColor,
                  ringColor: ringBlue,
                  iconColor: iconYellow,
                  size: size,
                ),
              ),
            );
          },
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

  // 🔥 UPDATED: Use service with caching
  Future<List<Map<String, dynamic>>> _fetchSeries() async {
    return CatalogService.fetchSeries();
  }

  // 🔥 UPDATED: Use service force refresh
  Future<void> _refresh() async {
    final fut = CatalogService.fetchSeries(forceRefresh: true);
    setState(() => _future = fut);
    await fut;
  }

  String? _abs(String? url) => ensureAbsoluteImageUrl(url);

  /// Визначаємо кількість книг у серії (для фільтрації та виводу)
  int _seriesBooksCountRaw(Map<String, dynamic> series) {
    final n = series['books_count'] ?? series['booksCount'];
    if (n is int) return n;
    if (n is num) return n.toInt();

    final fromStr = int.tryParse(n?.toString() ?? '');
    if (fromStr != null) return fromStr;

    final books = series['books'];
    if (books is List) return books.length;

    return 0;
  }

  bool _hasBooks(Map<String, dynamic> series) => _seriesBooksCountRaw(series) > 0;

  String? _seriesCover(Map<String, dynamic> series) {
    final firstCover =
    (series['first_cover'] ?? series['firstCover'])?.toString();
    if (firstCover != null && firstCover.isNotEmpty) return _abs(firstCover);

    final booksRaw = series['books'];
    if (booksRaw is List && booksRaw.isNotEmpty) {
      final Map<String, dynamic> b =
      Map<String, dynamic>.from(booksRaw.first);
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

  String _seriesTitle(Map<String, dynamic> series) {
    return (series['title'] ?? series['name'] ?? 'Серія')
        .toString()
        .trim();
  }

  String? _seriesDescription(Map<String, dynamic> series) {
    final d = (series['description'] ?? series['desc'])?.toString().trim();
    if (d == null || d.isEmpty) return null;
    return d;
  }

  String _seriesBooksCount(Map<String, dynamic> series) {
    return _seriesBooksCountRaw(series).toString();
  }

  Future<void> _openSeries(
      BuildContext context,
      Map<String, dynamic> series,
      ) async {
    final id = (series['id'] ?? series['series_id'])?.toString();
    final title = _seriesTitle(series);
    if (id == null || id.isEmpty) return;

    // 🔥 Note: We are not prefetching here anymore because SeriesBooksListScreen
    // will now handle fetching via the cached service efficiently.
    // Passing just the ID and Title is enough.

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeriesBooksListScreen(
          title: title.isEmpty ? 'Серія' : title,
          seriesId: id,
          initialBooks: null, // Let the screen fetch from cache
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
          final data = (s.data ?? const <Map<String, dynamic>>[])
              .where(_hasBooks)
              .toList();

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

          // 👉 Одна серія = один рядок
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              // 🔥 УВЕЛИЧЕННЫЙ ОТСТУП СНИЗУ ДЛЯ FAB
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
    factor = 1.5; // большие планшеты/десктоп
  } else if (screenW >= 720) {
    factor = 1.35; // планшеты 8–10"
  } else if (screenW >= 600) {
    factor = 1.25; // большие телефоны / маленькие планшеты
  } else if (screenW >= 480) {
    factor = 1.15; // широкие телефоны
  } else if (screenW >= 360) {
    factor = 1.0; // типичные телефоны
  } else {
    factor = 0.92; // сверхузкие (малые) устройства
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
                      : CachedNetworkImage(
                    imageUrl: coverUrl!,
                    cacheManager: BookaImageCacheManager.instance,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 180),
                    errorWidget: (_, __, ___) =>
                        placeholderBuilder(coverW, coverH),
                    progressIndicatorBuilder: (_, __, ___) =>
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: LoadingIndicator(size: 22),
                      ),
                    ),
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
                        style: t.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
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
                          color:
                          t.colorScheme.onSurface.withOpacity(0.85),
                          height: 1.28,
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Книг в серии
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.colorScheme.primary.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.20
                              : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: t.colorScheme.primary.withOpacity(
                            Theme.of(context).brightness ==
                                Brightness.dark
                                ? 0.40
                                : 0.25,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.library_books_rounded,
                            size: 16,
                            color: t.colorScheme.primary,
                          ),
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
    final base = t.colorScheme.surfaceVariant
        .withOpacity(t.brightness == Brightness.dark ? 0.24 : 0.35);

    final screenW = MediaQuery.of(context).size.width;
    final coverSize = _adaptiveCoverSize(screenW);

    Widget block({double w = 100, double h = 16, double r = 8}) => Container(
      width: w,
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
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

// =========================================================
// 🔥 ТА САМАЯ НАРЯДНАЯ КНОПКА (ВРАЩАЮЩАЯСЯ ПЛАСТИНКА) 🔥
// =========================================================
class _FancySpinningFab extends StatefulWidget {
  final VoidCallback onTap;
  final bool isPlaying;
  final Color bgColor;
  final Color ringColor;
  final Color iconColor;
  final double size; // Общий размер кнопки

  const _FancySpinningFab({
    Key? key,
    required this.onTap,
    required this.isPlaying,
    required this.bgColor,
    required this.ringColor,
    required this.iconColor,
    required this.size,
  }) : super(key: key);

  @override
  State<_FancySpinningFab> createState() => _FancySpinningFabState();
}

class _FancySpinningFabState extends State<_FancySpinningFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Полный оборот за 15 секунд (медленно и красиво)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _FancySpinningFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_controller.isAnimating) {
          _controller.repeat();
        }
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double fullSize = widget.size;

    final double innerSize = fullSize * 0.48;
    final double iconSize = fullSize * 0.42;
    final double logoPadding = fullSize * 0.01;

    return Semantics(
      button: true,
      label: widget.isPlaying ? 'Пауза' : 'Відтворити',
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. 🔥 ВРАЩАЮЩЕЕСЯ ВНЕШНЕЕ КОЛЬЦО (ПЛАСТИНКА)
          RotationTransition(
            turns: _controller,
            child: Container(
              width: fullSize,
              height: fullSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.ringColor, // Синяя оболочка
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(logoPadding),
                child: Image.asset(
                  'lib/assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // 2. СТАТИЧНЫЙ ЦЕНТР С ИКОНКОЙ
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.bgColor, // Темная или Primary(0.8)
            ),
            child: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: widget.iconColor, // Желтый
              size: iconSize,
            ),
          ),

          // 3. ОБЛАСТЬ НАЖАТИЯ (INKWELL)
          SizedBox(
            width: fullSize,
            height: fullSize,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}