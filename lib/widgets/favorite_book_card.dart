// lib/widgets/favorite_book_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants.dart';
import '../core/network/image_cache.dart';

/// Картка улюбленої книги — компактна, підходить для списків.
/// Підтримує як абсолютні URL, так і відносні шляхи з /storage.
class FavoriteBookCard extends StatelessWidget {
  final Map<String, dynamic> book;

  /// Абсолютний URL обкладинки (за бажанням можна передати зовні).
  final String? coverUrl;

  const FavoriteBookCard({
    super.key,
    required this.book,
    this.coverUrl,
  });

  /// Витягує thumb_url або cover_url з мапи книги.
  /// Якщо шлях відносний — повертає абсолютний через fullResourceUrl('storage/...').
  String? _resolveThumbOrCoverUrl(Map<String, dynamic> b) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? url =
        pick(b['thumb_url'] ?? b['thumbUrl']) ?? pick(b['cover_url'] ?? b['coverUrl']);
    if (url == null) return null;

    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url;
    }

    if (lower.startsWith('storage/')) {
      return fullResourceUrl(url);
    }
    if (lower.startsWith('/storage/')) {
      return fullResourceUrl(url.substring(1));
    }
    return fullResourceUrl('storage/$url');
  }

  /// Формує ім'я автора з можливих варіантів поля.
  String _authorName(Map<String, dynamic> b) {
    final a = b['author'];
    if (a is Map && a['name'] != null) return a['name'].toString().trim();
    if (a is String && a.trim().isNotEmpty) return a.trim();
    final an = b['author_name']?.toString();
    if (an != null && an.trim().isNotEmpty) return an.trim();
    return 'Автор невідомий';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;

    final String? rawUrl = coverUrl ?? _resolveThumbOrCoverUrl(book);
    final String? imageUrl =
    (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : null;

    final String title = (book['title'] ?? 'Без назви').toString();
    final String author = _authorName(book);

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null
                  ? CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: BookaImageCacheManager.instance,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                useOldImageOnUrlChange: true,
                placeholder: (ctx, _) => _coverPlaceholder(isDark),
                errorWidget: (ctx, _, __) => Icon(
                  Icons.broken_image,
                  size: 64,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              )
                  : _coverPlaceholder(isDark),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Плейсхолдер для обкладинки
  Widget _coverPlaceholder(bool isDark) {
    return Container(
      width: 64,
      height: 64,
      color: isDark ? Colors.white10 : Colors.black12,
      alignment: Alignment.center,
      child: Icon(
        Icons.book,
        size: 40,
        color: isDark ? Colors.white54 : Colors.black45,
      ),
    );
  }
}
