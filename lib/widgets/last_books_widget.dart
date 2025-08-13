import 'package:flutter/material.dart';
import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class LastBooksWidget extends StatefulWidget {
  final List<Book> books;

  const LastBooksWidget({super.key, required this.books});

  @override
  State<LastBooksWidget> createState() => _LastBooksWidgetState();
}

class _LastBooksWidgetState extends State<LastBooksWidget> {
  List<Book> _lastBooks = [];

  @override
  void initState() {
    super.initState();
    _processBooks();
  }

  @override
  void didUpdateWidget(covariant LastBooksWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пересчитываем список только если входные данные изменились
    if (widget.books != oldWidget.books) {
      _processBooks();
    }
  }

  // Логика сортировки и выбора вынесена из build метода
  void _processBooks() {
    if (widget.books.isEmpty) {
      _lastBooks = [];
      return;
    }
    // Сортируем по ID в убывающем порядке, чтобы получить самые новые
    final sorted = List<Book>.from(widget.books)..sort((a, b) => b.id.compareTo(a.id));
    // Берем первые 6
    _lastBooks = sorted.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastBooks.isEmpty) {
      return const SizedBox.shrink(); // Не показывать ничего, если книг нет
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text(
            'Новинки',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 180, // Задаем фиксированную высоту для списка
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _lastBooks.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (context, index) {
              final book = _lastBooks[index];
              return _BookCoverItem(book: book);
            },
          ),
        ),
      ],
    );
  }
}

// Отдельный виджет для элемента списка для лучшей производительности и читаемости
class _BookCoverItem extends StatelessWidget {
  final Book book;

  const _BookCoverItem({required this.book});

  @override
  Widget build(BuildContext context) {
    final imageUrl = book.displayCoverUrl;
    const double height = 160;
    const double width = height * (2 / 3); // Сохраняем соотношение сторон 2:3

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
