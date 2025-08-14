// ПУТЬ: lib/widgets/listened_book_card.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants.dart'; // fullResourceUrl(...)
import '../core/network/image_cache.dart'; // BookaImageCacheManager

class ListenedBookCard extends StatelessWidget {
  final Map<String, dynamic> book;

  /// Абсолютный URL, если уже вычислен снаружи.
  /// Если null — сам возьмём thumb_url -> cover_url из [book].
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

    String? url =
        pick(b['thumb_url'] ?? b['thumbUrl']) ?? pick(b['cover_url'] ?? b['coverUrl']);
    if (url == null) return null;

    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url; // уже абсолютный
    }
    // относительный -> собрать абсолютный
    if (lower.startsWith('/storage/')) return fullResourceUrl(url.substring(1));
    if (lower.startsWith('storage/')) return fullResourceUrl(url);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String title = (book['title'] ?? 'Без названия').toString();
    final String author = _authorName(book);
    final String? rawUrl = coverUrl ?? _resolveThumbOrCoverUrl(book);
    final String? imageUrl =
    (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : null;

    final Widget leadingWidget = (imageUrl != null)
        ? ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        cacheManager: BookaImageCacheManager.instance,
        width: 48,
        height: 64,
        fit: BoxFit.cover,
        useOldImageOnUrlChange: true,
        placeholder: (ctx, _) => _thumbPlaceholder(isDark),
        errorWidget: (ctx, _, __) => Icon(
          Icons.broken_image,
          size: 48,
          color: isDark ? Colors.white30 : Colors.black26,
        ),
      ),
    )
        : _thumbPlaceholder(isDark);

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

  Widget _thumbPlaceholder(bool isDark) {
    return Container(
      width: 48,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.book, size: 32, color: isDark ? Colors.white54 : Colors.black45),
    );
  }
}
