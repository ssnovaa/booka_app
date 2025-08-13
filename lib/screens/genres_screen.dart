import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../models/genre.dart';
import '../models/book.dart';
import '../services/catalog_service.dart';
import '../widgets/book_card.dart';

class GenresScreen extends StatefulWidget {
  final VoidCallback? onReturnToMain; // Новый параметр!

  const GenresScreen({super.key, this.onReturnToMain});

  @override
  State<GenresScreen> createState() => _GenresScreenState();
}

class _GenresScreenState extends State<GenresScreen> {
  List<Genre> genres = [];
  Genre? selectedGenre;
  List<Book> books = [];
  bool isLoadingGenres = false;
  bool isLoadingBooks = false;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchGenres();
  }

  Future<void> fetchGenres() async {
    setState(() {
      isLoadingGenres = true;
      error = null;
    });
    try {
      genres = await CatalogService.fetchGenres();
      setState(() {
        selectedGenre = null;
      });
    } catch (e) {
      error = 'Помилка завантаження жанрів: $e';
    } finally {
      setState(() => isLoadingGenres = false);
    }
  }

  Future<void> fetchBooksForGenre(Genre genre) async {
    setState(() {
      isLoadingBooks = true;
      error = null;
      books = [];
    });
    try {
      books = await CatalogService.fetchBooks(genre: genre);
    } catch (e) {
      error = 'Помилка завантаження книг: $e';
    } finally {
      setState(() => isLoadingBooks = false);
    }
  }

  // ----------- БЛОК КАСТОМНОГО BACK-ОБРАБОТЧИКА -----------
  Future<bool> _onWillPop() async {
    if (selectedGenre != null) {
      setState(() {
        selectedGenre = null;
        books = [];
      });
      return false; // Остаемся на экране, сбрасываем жанр
    }
    // Если жанр не выбран — вызвать onReturnToMain (например, сменить таб)
    if (widget.onReturnToMain != null) {
      widget.onReturnToMain!();
    }
    // Не даём обычного pop!
    return false;
  }
  // --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        // appBar: AppBar(title: const Text('Жанри')),
        body: isLoadingGenres
            ? const Center(child: CircularProgressIndicator())
            : genres.isEmpty
            ? const Center(child: Text('Жанрів не знайдено'))
            : selectedGenre == null
            ? SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: genres.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final genre = genres[index];
                return GestureDetector(
                  onTap: () async {
                    setState(() {
                      selectedGenre = genre;
                      books = [];
                    });
                    await fetchBooksForGenre(genre);
                  },
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildGenreImage(genre),
                          const SizedBox(height: 10),
                          AutoSizeText(
                            genre.name,
                            textAlign: TextAlign.center,
                            minFontSize: 10,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        )
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: genres.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final genre = genres[index];
                  final isSelected = selectedGenre?.id == genre.id;
                  return GestureDetector(
                    onTap: () async {
                      setState(() {
                        selectedGenre = genre;
                        books = [];
                      });
                      await fetchBooksForGenre(genre);
                    },
                    child: Card(
                      color: isSelected ? Colors.purple.shade100 : Colors.white,
                      elevation: isSelected ? 4 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isSelected
                            ? BorderSide(color: Colors.purple.shade400, width: 2)
                            : BorderSide.none,
                      ),
                      child: Center(
                        child: AutoSizeText(
                          genre.name,
                          textAlign: TextAlign.center,
                          minFontSize: 10,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.purple : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: isLoadingBooks
                  ? const Center(child: CircularProgressIndicator())
                  : books.isEmpty
                  ? const Center(child: Text('Книг не знайдено для цього жанру'))
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return BookCardWidget(book: book);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenreImage(Genre genre) {
    final Map<int, String> genreImages = {
      5: 'lib/assets/images/fantasy.png',
      2: 'lib/assets/images/detective.png',
      4: 'lib/assets/images/romance.png',
      // ...
    };
    final asset = genreImages[genre.id] ?? 'lib/assets/images/logo.png';
    return Image.asset(
      asset,
      width: 82,
      height: 82,
      fit: BoxFit.cover,
    );
  }
}
