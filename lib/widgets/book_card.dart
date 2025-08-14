// lib/widgets/book_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class BookCardWidget extends StatelessWidget {
  final Book book;

  const BookCardWidget({Key? key, required this.book}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageUrl = (book.displayCoverUrl ?? '').trim();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // [STYLE] Токены
    const double cardRadius = 14;
    const double imageWidth = 96; // заметно крупнее
    const double vPad = 12;
    const double hPad = 12;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
        );
      },
      borderRadius: BorderRadius.circular(cardRadius),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withOpacity(0.25) : Colors.black12,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: theme.dividerColor.withOpacity(isDark ? 0.15 : 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [IMG] Обложка 2:3, без кропа по ширине блока
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: imageWidth,
                  height: imageWidth * 1.5, // 2:3
                  color: isDark ? Colors.white10 : Colors.black12,
                  alignment: Alignment.center,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: imageWidth,
                    height: imageWidth * 1.5,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => Icon(
                      Icons.broken_image,
                      size: 36,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  )
                      : Icon(Icons.book, size: 40, color: isDark ? Colors.white54 : Colors.black45),
                ),
              ),

              const SizedBox(width: 12),

              // [TEXT] Контент
              Expanded(
                child: SizedBox(
                  height: imageWidth * 1.5, // выравниваем по высоте с обложкой
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок
                      Text(
                        (book.title ?? '').trim().isNotEmpty ? book.title!.trim() : 'Без названия',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Автор (серый вторичный)
                      if ((book.author ?? '').trim().isNotEmpty)
                        Text(
                          book.author!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Жанры (до 3 штук), компактный серый текст
                      if (book.genres.isNotEmpty)
                        Text(
                          'Жанры: ${book.genres.take(3).join(", ")}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),

                      // Spacer + метаданные снизу одной строкой
                      const Spacer(),

                      // Низ карточки: длительность + серия (если есть)
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if ((book.duration ?? '').trim().isNotEmpty)
                            _MetaChip(
                              icon: Icons.schedule,
                              text: book.duration!.trim(),
                            ),
                          if (((book.series ?? '').toString().trim()).isNotEmpty)
                            _MetaChip(
                              icon: Icons.auto_stories_outlined,
                              text: (book.series ?? '').toString().trim(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// [WIDGET] Маленький «чип» метаданных (иконка + текст)
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
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withOpacity(isDark ? 0.18 : 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.iconTheme.color?.withOpacity(0.75)),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
