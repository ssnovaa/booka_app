// lib/screens/series_books_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/constants.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/screens/book_detail_screen.dart';
import 'package:booka_app/widgets/custom_bottom_nav_bar.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/screens/profile_screen.dart';
import 'package:booka_app/core/network/image_cache.dart';

// 🔥 IMPORTS FOR CACHING AND FAVORITES
import 'package:booka_app/services/catalog_service.dart';
import 'package:booka_app/widgets/add_to_favorites_button.dart';

enum NumberCorner { topRight, topLeft, bottomRight, bottomLeft }

/// Сторінка — список книг серії.
class SeriesBooksListScreen extends StatefulWidget {
  final String title;
  final String seriesId;
  final List<Map<String, dynamic>>? initialBooks;

  final NumberCorner numberCorner;
  final double numberOpacity;
  final EdgeInsets numberPadding;
  final double numberFontSize;

  const SeriesBooksListScreen({
    Key? key,
    required this.title,
    required this.seriesId,
    this.initialBooks,
    this.numberCorner = NumberCorner.topRight,
    this.numberOpacity = 0.70,
    this.numberPadding = const EdgeInsets.only(top: 5, right: 25),
    this.numberFontSize = 42,
  }) : super(key: key);

  @override
  State<SeriesBooksListScreen> createState() => _SeriesBooksListScreenState();
}

class _SeriesBooksListScreenState extends State<SeriesBooksListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.initialBooks != null
        ? Future.value(widget.initialBooks!)
        : _fetchBooks();
  }

  Future<List<Map<String, dynamic>>> _fetchBooks({bool force = false}) async {
    return CatalogService.fetchSeriesBooks(widget.seriesId, forceRefresh: force);
  }

  Future<void> _refresh() async {
    final fut = _fetchBooks(force: true);
    setState(() => _future = fut);
    await fut;
  }

  // ---------- допоміжні функції ----------

  String? _cover(Map<String, dynamic> m) {
    final thumb = (m['thumb_url'] ?? m['thumbUrl'])?.toString();
    final cover = (m['cover_url'] ?? m['coverUrl'])?.toString();
    return ensureAbsoluteImageUrl(thumb ?? cover);
  }

  int _seriesNumber(Map<String, dynamic> m, int fallbackIndex) {
    final candidates = [
      m['series_number'],
      m['seriesNumber'],
      m['number_in_series'],
      m['numberInSeries'],
      m['series_index'],
      m['seriesIndex'],
      m['order'],
      m['index'],
      m['seq'],
    ];
    for (final v in candidates) {
      final s = v?.toString();
      if (s == null) continue;
      final n = int.tryParse(s);
      if (n != null && n > 0) return n;
    }
    return fallbackIndex + 1;
  }

  String? _firstGenre(Map<String, dynamic> m) {
    final g = m['genres'];
    if (g is List && g.isNotEmpty) return g.first.toString();
    return null;
  }

  String _formatDuration(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.contains(':')) return s;
    final minutes = int.tryParse(s) ?? 0;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '$h год ${m.toString().padLeft(2, '0')} хв' : '$m хв';
  }

  Map<String, dynamic> _normalized(Map<String, dynamic> m) {
    final map = Map<String, dynamic>.from(m);
    final abs = _cover(map);
    if (abs != null) {
      map['thumb_url'] = abs;
      map['thumbUrl'] = abs;
      map['cover_url'] = abs;
      map['coverUrl'] = abs;
    }
    return map;
  }

  void _openBook(Map<String, dynamic> raw) {
    try {
      final book = Book.fromJson(_normalized(raw));
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити книгу')),
      );
    }
  }

  // ---------- bottom nav ----------

  void _goToMain(int tabIndex) {
    final ms = MainScreen.of(context);
    if (ms != null) {
      ms.setTab(tabIndex);
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainScreen(initialIndex: tabIndex)),
            (r) => false,
      );
    }
  }

  Future<void> _openPlayer() async {
    final ap = context.read<AudioPlayerProvider>();
    final book = ap.currentBook;
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Немає поточного прослуховування')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
    );
  }

  void _onBottomTap(int i) {
    switch (i) {
      case 0:
        _goToMain(0);
        break; // Жанри
      case 1:
        _goToMain(1);
        break; // Каталог
      case 2:
        _openPlayer();
        break;
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        break;
    }
  }

  // ---------- UI-помічники ----------

  Widget _chip(BuildContext context, String text, {IconData? icon}) {
    final t = Theme.of(context);
    final bg = t.colorScheme.surfaceVariant.withOpacity(
      t.brightness == Brightness.dark ? 0.20 : 0.35,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: t.dividerColor.withOpacity(
            t.brightness == Brightness.dark ? 0.18 : 0.10,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: t.colorScheme.onSurface.withOpacity(0.7)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: t.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverImage(BuildContext context, String? url) {
    final t = Theme.of(context);
    final placeholder = Container(
      width: 112,
      height: 160,
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceVariant
            .withOpacity(t.brightness == Brightness.dark ? 0.24 : 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Icon(Icons.book_rounded, size: 28)),
    );

    if (url == null || url.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheManager: BookaImageCacheManager.instance,
        width: 112,
        height: 160,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 180),
        errorWidget: (_, __, ___) => placeholder,
        progressIndicatorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }

  Widget _numberText(BuildContext context, int n) {
    final t = Theme.of(context);
    final op = widget.numberOpacity.clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: true,
      child: Text(
        '$n',
        style: TextStyle(
          fontSize: widget.numberFontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: t.colorScheme.onSurface.withOpacity(op),
          shadows: const [Shadow(blurRadius: 2, color: Colors.transparent)],
        ),
      ),
    );
  }

  Widget _positionedNumber(BuildContext context, int n) {
    final p = widget.numberPadding;
    switch (widget.numberCorner) {
      case NumberCorner.topRight:
        return Positioned(top: p.top, right: p.right, child: _numberText(context, n));
      case NumberCorner.topLeft:
        return Positioned(top: p.top, left: p.left, child: _numberText(context, n));
      case NumberCorner.bottomRight:
        return Positioned(bottom: p.bottom, right: p.right, child: _numberText(context, n));
      case NumberCorner.bottomLeft:
        return Positioned(bottom: p.bottom, left: p.left, child: _numberText(context, n));
    }
  }

  Widget _bookCard(BuildContext context, Map<String, dynamic> m, int index) {
    final t = Theme.of(context);
    final url = _cover(m);
    final n = _seriesNumber(m, index);
    final title = (m['title'] ?? '').toString().trim();
    final author = (m['author'] ?? m['author_name'] ?? '').toString().trim();
    final desc = (m['description'] ?? m['short_description'] ?? m['annotation'] ?? '')
        .toString()
        .trim();
    final duration = _formatDuration(m['duration'] ?? m['length']);
    final g = _firstGenre(m);

    final rawId = m['id'] ?? m['book_id'] ?? m['bookId'];
    final bookId = (rawId != null) ? int.tryParse(rawId.toString()) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openBook(m),
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: t.colorScheme.primary.withOpacity(
                        t.brightness == Brightness.dark ? 0.10 : 0.06,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: t.dividerColor.withOpacity(
                      t.brightness == Brightness.dark ? 0.15 : 0.08,
                    ),
                  ),
                ),
                // 🔥 ЗМІНЕНО: Головний контейнер тепер Column, щоб опис був знизу
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Верхня частина: Обкладинка + Інформація
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _coverImage(context, url),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, right: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.isEmpty ? 'Без назви' : title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                if (author.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: t.textTheme.bodySmall?.color?.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (duration.isNotEmpty)
                                      _chip(context, duration, icon: Icons.schedule_rounded),

                                    // 🔥 Кнопка "Вибране"
                                    if (bookId != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6, bottom: 4),
                                        child: AddToFavoritesButton(
                                          bookId: bookId,
                                          style: AddFavStyle.bar,
                                          size: 22,
                                        ),
                                      ),

                                    if (g != null) _chip(context, g),
                                  ],
                                ),
                                // ❌ Опис звідси прибрали
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 🔥 Опис тепер тут: на всю ширину під верхнім блоком
                    const SizedBox(height: 12),
                    Text(
                      desc.isEmpty ? 'Опис відсутній.' : desc,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              _positionedNumber(context, n),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 6,
                itemBuilder: (_, i) => Container(
                  height: 184,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surfaceVariant.withOpacity(
                      t.brightness == Brightness.dark ? 0.18 : 0.30,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              );
            }

            final data = s.data ?? const <Map<String, dynamic>>[];
            if (data.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      widget.title,
                      style: t.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'У серії поки що немає книг',
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      widget.title,
                      style: t.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                }
                return _bookCard(context, data[i - 1], i - 1);
              },
            );
          },
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1,
        onTap: _onBottomTap,
        onOpenPlayer: _openPlayer,
        onPlayerTap: _openPlayer,
      ),
    );
  }
}