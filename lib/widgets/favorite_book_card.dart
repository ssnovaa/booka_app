import 'package:flutter/material.dart';
import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class FavoriteBookCard extends StatelessWidget {
  final Book book;

  const FavoriteBookCard({
    super.key,
    required this.book,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Обертываем Card в SizedBox, чтобы предоставить ограниченную ширину,
    // что решает проблему с компоновкой RenderFlex.
    return SizedBox(
      width: 300, // Установите желаемую ширину карточки.
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                _buildCover(context, book.displayCoverUrl),
                const SizedBox(width: 16),
                Expanded(child: _buildInfo(context, book)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Виджет для отображения обложки
  Widget _buildCover(BuildContext context, String? imageUrl) {
    const double size = 64;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: isDark ? Colors.white10 : Colors.black12,
        child: (imageUrl != null && imageUrl.isNotEmpty)
            ? Image.network(
          imageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, size: size, color: isDark ? Colors.white30 : Colors.black26),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        )
            : Image.asset(
          'lib/assets/images/logo.png', // Обновленный путь к ассету
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.book_outlined, size: 40, color: isDark ? Colors.white54 : Colors.black45),
        ),
      ),
    );
  }

  // Виджет для отображения текстовой информации
  Widget _buildInfo(BuildContext context, Book book) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          book.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
