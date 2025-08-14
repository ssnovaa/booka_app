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
    final popularBooks = getPopularBooks();
    if (popularBooks.isEmpty) return const SizedBox();

    final List<List<Book>> slides = [];
    for (int i = 0; i < popularBooks.length; i += 3) {
      slides.add(popularBooks.sublist(i, (i + 3) > popularBooks.length ? popularBooks.length : (i + 3)));
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, left: 8, right: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                'Найпопулярніші',
                style: GoogleFonts.pangolin(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[900],
                  letterSpacing: 0.5,
                ),
              ),
            ),
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
                                color: Colors.grey[200],
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 2,
                                    offset: Offset(1, 2),
                                  ),
                                ],
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
    return Container(
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(Icons.book, size: 40, color: Colors.black45),
    );
  }
}

class _TileError extends StatelessWidget {
  const _TileError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image, size: 40),
    );
  }
}
