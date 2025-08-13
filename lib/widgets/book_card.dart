import 'package:flutter/material.dart';
import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class BookCardWidget extends StatelessWidget {
  final Book book;

  const BookCardWidget({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 1 : 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.dividerColor.withOpacity(isDark ? 0.15 : 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias, // Для корректного скругления InkWell
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(context, book.displayCoverUrl),
              const SizedBox(width: 12),
              Expanded(child: _buildInfo(context, book)),
            ],
          ),
        ),
      ),
    );
  }

  // Виджет для отображения обложки
  Widget _buildCover(BuildContext context, String? imageUrl) {
    const double imageWidth = 96;
    const double imageHeight = imageWidth * 1.5; // Соотношение 2:3
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: imageWidth,
        height: imageHeight,
        color: isDark ? Colors.white10 : Colors.black12,
        child: (imageUrl != null && imageUrl.isNotEmpty)
            ? Image.network(
          imageUrl,
          width: imageWidth,
          height: imageHeight,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: isDark ? Colors.white30 : Colors.black26,
          ),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        )
            : Icon(Icons.book_outlined, size: 40, color: isDark ? Colors.white54 : Colors.black45),
      ),
    );
  }

  // Виджет для отображения текстовой информации
  Widget _buildInfo(BuildContext context, Book book) {
    const double imageHeight = 96 * 1.5;
    final theme = Theme.of(context);

    return SizedBox(
      height: imageHeight, // Выравниваем по высоте с обложкой
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book.title.trim().isNotEmpty ? book.title.trim() : 'Без названия',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          if (book.author.trim().isNotEmpty)
            Text(
              book.author.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          const SizedBox(height: 8),
          if (book.genres.isNotEmpty)
            Text(
              'Жанры: ${book.genres.take(3).join(", ")}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          const Spacer(), // Занимает все доступное пространство
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (book.duration.trim().isNotEmpty)
                _MetaChip(
                  icon: Icons.schedule_rounded,
                  text: book.duration.trim(),
                ),
              if (book.series != null && book.series!.trim().isNotEmpty)
                _MetaChip(
                  icon: Icons.auto_stories_outlined,
                  text: book.series!.trim(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Маленький «чип» метаданных (иконка + текст)
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.iconTheme.color?.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
