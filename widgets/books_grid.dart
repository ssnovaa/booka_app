// lib/widgets/books_grid.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/models/book.dart';
import 'package:booka_app/screens/book_detail_screen.dart';
import 'package:booka_app/constants.dart';
import 'package:booka_app/widgets/loading_indicator.dart'; // ← Lottie-лоадер замість стандартного бублика

class BooksGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String? Function(Map<String, dynamic>) resolveUrl;

  const BooksGrid({
    Key? key,
    required this.items,
    required this.resolveUrl,
  }) : super(key: key);

  double _aspect(BuildContext context) {
    final mq = MediaQuery.of(context);
    final shortest = mq.size.shortestSide;
    final isTablet = shortest >= 600;
    final t = mq.textScaleFactor.clamp(1.0, 1.5);
    final base = isTablet ? 0.74 : 0.70;
    return (base / (t * 0.95)).clamp(0.60, 0.85);
  }

  String _titleOf(Map<String, dynamic> m) =>
      (m['title'] ?? m['name'] ?? '').toString().trim();

  String _authorOf(Map<String, dynamic> m) {
    final v = m['author'] ?? m['authors'] ?? '';
    if (v is Map && v['name'] != null) return v['name'].toString().trim();
    return v.toString().trim();
  }

  String _durationOf(Map<String, dynamic> m) =>
      (m['duration'] ?? m['total_duration'] ?? '').toString().trim();

  String _seriesOf(Map<String, dynamic> m) {
    final v = m['series'] ?? m['sequence'] ?? '';
    if (v is Map && v['name'] != null) return v['name'].toString().trim();
    return v.toString().trim();
  }

  void _openDetails(BuildContext context, Map<String, dynamic> m) {
    try {
      final book = Book.fromJson(Map<String, dynamic>.from(m));
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити книгу')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: _aspect(context),
      ),
      itemBuilder: (context, i) {
        final m = items[i];
        final coverUrl = ensureAbsoluteImageUrl(resolveUrl(m));
        final title = _titleOf(m);
        final author = _authorOf(m);
        final duration = _durationOf(m);
        final series = _seriesOf(m);

        final isDark = theme.brightness == Brightness.dark;

        return InkWell(
          onTap: () => _openDetails(context, m),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.dividerColor.withOpacity(isDark ? 0.16 : 0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(isDark ? 0.18 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, bc) {
                const imageAspect = 3 / 4;
                const maxImageFraction = 0.62;

                final w = bc.maxWidth;
                final h = bc.maxHeight;
                final naturalImageH = w / imageAspect;
                final maxImageH = h * maxImageFraction;
                final imageH =
                naturalImageH > maxImageH ? maxImageH : naturalImageH;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                      child: SizedBox(
                        height: imageH,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: (coverUrl == null || coverUrl.isEmpty)
                              ? Container(
                            color: isDark ? Colors.white10 : Colors.black12,
                            child: const Center(
                              child: Icon(Icons.book_rounded, size: 32),
                            ),
                          )
                              : CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 120),
                            // 🔄 Lottie-лоадер під час завантаження обкладинки
                            placeholder: (_, __) => const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: LoadingIndicator(size: 20),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: isDark ? Colors.white10 : Colors.black12,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title.isNotEmpty ? title : 'Без назви',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                            ),
                          ),
                          if (author.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color
                                    ?.withOpacity(0.82),
                                fontWeight: FontWeight.w600,
                                height: 1.05,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),

                          // 🔻 Рядок мета: [тривалість] [серія]
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: _withSpacing([
                                    if (duration.isNotEmpty)
                                      _MetaChipSmall(
                                        icon: Icons.schedule,
                                        text: duration,
                                      ),
                                    if (series.isNotEmpty)
                                      _MetaChipSmall(
                                        icon: Icons.auto_stories_outlined,
                                        text: series,
                                      ),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Локальний хелпер для відступів між елементами в рядку
  List<Widget> _withSpacing(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 6));
      out.add(children[i]);
    }
    return out;
  }
}

class _MetaChipSmall extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaChipSmall({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: t.dividerColor.withOpacity(isDark ? 0.18 : 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.iconTheme.color?.withOpacity(0.75)),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
