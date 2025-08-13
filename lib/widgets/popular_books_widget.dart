import 'package:flutter/material.dart';
import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class PopularBooksWidget extends StatefulWidget {
  final List<Book> books;

  const PopularBooksWidget({super.key, required this.books});

  @override
  State<PopularBooksWidget> createState() => _PopularBooksWidgetState();
}

class _PopularBooksWidgetState extends State<PopularBooksWidget> {
  List<Book> _popularBooks = [];

  @override
  void initState() {
    super.initState();
    _processBooks();
  }

  @override
  void didUpdateWidget(covariant PopularBooksWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.books != oldWidget.books) {
      _processBooks();
    }
  }

  // Логика получения популярных книг вынесена из build метода
  void _processBooks() {
    if (widget.books.isEmpty) {
      _popularBooks = [];
      return;
    }
    // Здесь можно добавить свою логику сортировки по популярности,
    // например, по количеству прослушиваний или рейтингу.
    // Пока что просто берем первые 6.
    _popularBooks = widget.books.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_popularBooks.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text(
            'Популярное',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 180, // Задаем фиксированную высоту для списка
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _popularBooks.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (context, index) {
              final book = _popularBooks[index];
              return _BookCoverItem(book: book);
            },
          ),
        ),
      ],
    );
  }
}

// Отдельный виджет для элемента списка.
// В идеале, его стоит вынести в отдельный файл, чтобы использовать и в LastBooksWidget.
class _BookCoverItem extends StatelessWidget {
  final Book book;

  const _BookCoverItem({required this.book});

  @override
  Widget build(BuildContext context) {
    final imageUrl = book.displayCoverUrl;
    const double height = 160;
    const double width = height * (2 / 3); // Соотношение сторон 2:3

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
          );
        },
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: (imageUrl != null && imageUrl.isNotEmpty)
              ? Image.network(
            imageUrl,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, size: 40, color: Colors.grey),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            },
          )
              : Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.book, size: 40, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
