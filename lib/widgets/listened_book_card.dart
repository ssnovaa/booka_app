// ПУТЬ: lib/widgets/listened_book_card.dart

import 'package:flutter/material.dart';
import '../constants.dart'; // для fullResourceUrl

class ListenedBookCard extends StatelessWidget {
  final Map<String, dynamic> book;

  /// Абсолютный URL изображения, если уже вычислен снаружи.
  /// Если null — виджет сам попытается взять thumb_url -> cover_url из [book].
  final String? coverUrl;

  const ListenedBookCard({
    Key? key,
    required this.book,
    this.coverUrl,
  }) : super(key: key);

  String? _resolveThumbOrCoverUrl(Map<String, dynamic> b) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? url = pick(b['thumb_url'] ?? b['thumbUrl']) ?? pick(b['cover_url'] ?? b['coverUrl']);
    if (url == null) return null;

    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url; // уже абсолютный
    }
    // относительный -> собрать абсолютный
    return fullResourceUrl('storage/$url');
  }

  String _authorName(Map<String, dynamic> b) {
    final a = b['author'];
    if (a is Map && a['name'] != null) return a['name'].toString();
    if (a is String && a.trim().isNotEmpty) return a.trim();
    final an = b['author_name']?.toString();
    if (an != null && an.trim().isNotEmpty) return an.trim();
    return 'Неизвестно';
  }

  @override
  Widget build(BuildContext context) {
    final String title = (book['title'] ?? 'Без названия').toString();
    final String author = _authorName(book);
    final String? imageUrl = coverUrl ?? _resolveThumbOrCoverUrl(book);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leadingWidget = (imageUrl != null)
        ? ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        imageUrl,
        width: 48,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.broken_image, size: 48, color: isDark ? Colors.white30 : Colors.black26),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: 48,
            height: 64,
            alignment: Alignment.center,
            color: isDark ? Colors.white10 : Colors.black12,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    )
        : Icon(Icons.book, size: 48, color: isDark ? Colors.white54 : Colors.black45);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: leadingWidget,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Автор: $author',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // onTap: () { /* при необходимости: открыть детальную */ },
      ),
    );
  }
}
