// ПУТЬ: lib/widgets/popular_books_widget.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/book.dart';
import '../screens/book_detail_screen.dart';
import '../core/network/image_cache.dart'; // BookaImageCacheManager

class PopularBooksWidget extends StatelessWidget {
  final List<Book> books;

  const PopularBooksWidget({Key? key, required this.books}) : super(key: key);

  List<Book> getPopularBooks() {
    if (books.isEmpty) return [];
    // Просто первые 6 (или подправь сортировку под себя)
    return List<Book>.from(books).take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final popularBooks = getPopularBooks();
    if (popularBooks.isEmpty) return const SizedBox();

    final List<List<Book>> slides = [];
    for (int i = 0; i < popularBooks.length; i += 3) {
      slides.add(
        popularBooks.sublist(
          i,
          (i + 3) > popularBooks.length ? popularBooks.length : (i + 3),
        ),
      );
    }

    // Контрастный заголовок для лайт/дарк тем
    final baseTitle = Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
    final titleStyle = GoogleFonts.pangolin(textStyle: baseTitle).copyWith(
      color: cs.onSurface.withOpacity(0.92),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );

    return Card(
      elevation: 0, // строже — без тени
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, left: 8, right: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок секции
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text('Найпопулярніші', style: titleStyle),
            ),

            // Карусель
            SizedBox(
              height: 164,
              child: PageView.builder(
                itemCount: slides.length,
                controller: PageController(viewportFraction: 0.95),
                itemBuilder: (context, index) {
                  final slide = slides[index];
                  return Row(
                    children: List.generate(3, (i) {
                      if (i < slide.length) {
                        final book = slide[i];
                        final imageUrl = book.displayCoverUrl; // thumb с фолбэком на cover

                        return Flexible(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookDetailScreen(book: book),
                                ),
                              );
                            },
                            child: Container(
                              height: 144,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                // строгая рамка вместо тени
                                border: Border.all(color: cs.outline, width: 1),
                                color: cs.surfaceVariant.withOpacity(0.35),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                cacheManager: BookaImageCacheManager.instance,
                                fit: BoxFit.cover,
                                useOldImageOnUrlChange: true,
                                placeholder: (ctx, _) => const _TilePlaceholder(),
                                errorWidget: (ctx, _, __) => const _TileError(),
                              )
                                  : const _TilePlaceholder(),
                            ),
                          ),
                        );
                      } else {
                        return const Flexible(child: SizedBox());
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TilePlaceholder extends StatelessWidget {
  const _TilePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceVariant.withOpacity(0.35),
      alignment: Alignment.center,
      child: Icon(Icons.book, size: 40, color: cs.onSurfaceVariant),
    );
  }
}

class _TileError extends StatelessWidget {
  const _TileError();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceVariant.withOpacity(0.35),
      alignment: Alignment.center,
      child: Icon(Icons.broken_image, size: 40, color: cs.onSurfaceVariant),
    );
  }
}
