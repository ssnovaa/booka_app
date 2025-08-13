// ПУТЬ: lib/widgets/last_books_widget.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class LastBooksWidget extends StatelessWidget {
  final List<Book> books;

  const LastBooksWidget({Key? key, required this.books}) : super(key: key);

  List<Book> getLastBooks() {
    if (books.isEmpty) return [];
    final sorted = List<Book>.from(books)..sort((a, b) => b.id.compareTo(a.id));
    return sorted.take(6).toList(); // ← при необходимости поменяй количество
  }

  @override
  Widget build(BuildContext context) {
    final lastBooks = getLastBooks();
    if (lastBooks.isEmpty) return const SizedBox();

    // Группируем по 3 в ряд для "карусели"
    final List<List<Book>> slides = [];
    for (int i = 0; i < lastBooks.length; i += 3) {
      slides.add(lastBooks.sublist(i, (i + 3) > lastBooks.length ? lastBooks.length : (i + 3)));
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, left: 8, right: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                'Найсвіжіші історії',
                style: GoogleFonts.pangolin(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[900],
                  letterSpacing: 0.2,
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
                        // ✅ КЛЮЧ: используем миниатюру с фолбэком на обложку
                        final imageUrl = book.displayCoverUrl;

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
                                  ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey[300],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image, size: 40),
                                ),
                              )
                                  : Container(
                                color: Colors.grey[300],
                                alignment: Alignment.center,
                                child: const Icon(Icons.book, size: 40),
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Пустой Flexible для выравнивания
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
