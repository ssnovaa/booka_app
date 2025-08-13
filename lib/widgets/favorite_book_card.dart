// ПУТЬ: lib/widgets/favorite_book_card.dart

import 'package:flutter/material.dart';
import '../constants.dart'; // для fullResourceUrl

class FavoriteBookCard extends StatelessWidget {
  final Map<String, dynamic> book;

  /// Абсолютный URL обложки/миниатюры (если уже рассчитан снаружи).
  /// Если null — виджет сам попробует достать thumb_url -> cover_url из [book].
  final String? coverUrl;

  const FavoriteBookCard({
    super.key,
    required this.book,
    this.coverUrl,
  });

  /// Берём thumb_url (если есть), иначе cover_url.
  /// Если путь относительный — конвертируем в абсолютный через fullResourceUrl('storage/...').
  String? _resolveThumbOrCoverUrl(Map<String, dynamic> b) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? url = pick(b['thumb_url'] ?? b['thumbUrl']) ?? pick(b['cover_url'] ?? b['coverUrl']);
    if (url == null) return null;

    // Уже абсолютный?
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url;
    }
    // Относительный -> собрать абсолютный
    return fullResourceUrl('storage/$url');
  }

  String _authorName(Map<String, dynamic> b) {
    final a = b['author'];
    if (a is Map && a['name'] != null) return a['name'].toString();
    if (a is String && a.trim().isNotEmpty) return a.trim();
    // иногда автор хранится как 'author_name'
    final an = b['author_name']?.toString();
    if (an != null && an.trim().isNotEmpty) return an.trim();
    return 'Автор неизвестен';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;

    final String? imageUrl = coverUrl ?? _resolveThumbOrCoverUrl(book);
    final String title = (book['title'] ?? 'Без названия').toString();
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
              child: (imageUrl != null)
                  ? Image.network(
                imageUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.broken_image, size: 64, color: isDark ? Colors.white30 : Colors.black26),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    color: isDark ? Colors.white10 : Colors.black12,
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              )
                  : Container(
                width: 64,
                height: 64,
                color: isDark ? Colors.white10 : Colors.black12,
                alignment: Alignment.center,
                child: Icon(Icons.book, size: 40, color: isDark ? Colors.white54 : Colors.black45),
              ),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
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
}
