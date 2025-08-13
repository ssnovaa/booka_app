import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../models/genre.dart';
import '../models/book.dart';
import '../services/catalog_service.dart'; // Предполагаем, что сервис существует
import '../widgets/book_card.dart';

class GenresScreen extends StatefulWidget {
  final VoidCallback? onReturnToMain;

  const GenresScreen({super.key, this.onReturnToMain});

  @override
  State<GenresScreen> createState() => _GenresScreenState();
}

class _GenresScreenState extends State<GenresScreen> {
  List<Genre> _genres = [];
  Genre? _selectedGenre;
  List<Book> _books = [];

  bool _isLoadingGenres = true;
  bool _isLoadingBooks = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchGenres();
  }

  Future<void> _fetchGenres() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGenres = true;
      _error = null;
    });
    try {
      _genres = await CatalogService.fetchGenres();
    } catch (e) {
      _error = 'Ошибка загрузки жанров: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoadingGenres = false);
      }
    }
  }

  Future<void> _fetchBooksForGenre(Genre genre) async {
    if (!mounted) return;
    setState(() {
      _isLoadingBooks = true;
      _error = null;
      _books = [];
    });
    try {
      _books = await CatalogService.fetchBooks(genre: genre);
    } catch (e) {
      _error = 'Ошибка загрузки книг: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoadingBooks = false);
      }
    }
  }

  void _selectGenre(Genre genre) {
    setState(() => _selectedGenre = genre);
    _fetchBooksForGenre(genre);
  }

  void _resetGenre() {
    setState(() {
      _selectedGenre = null;
      _books = [];
    });
  }

  Future<bool> _onWillPop() async {
    if (_selectedGenre != null) {
      _resetGenre();
      return false; // Остаемся на экране, сбрасываем жанр
    }
    widget.onReturnToMain?.call();
    return false; // Не даём стандартного pop
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingGenres) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_genres.isEmpty) {
      return const Center(child: Text('Жанры не найдены'));
    }

    // Показываем либо сетку жанров, либо детали выбранного жанра
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _selectedGenre == null
          ? _buildGenreGrid()
          : _buildGenreDetailView(),
    );
  }

  Widget _buildGenreGrid() {
    return GridView.builder(
      key: const ValueKey('genre_grid'), // Ключ для анимации
      padding: const EdgeInsets.all(12),
      itemCount: _genres.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final genre = _genres[index];
        return _GenreCard(
          genre: genre,
          onTap: () => _selectGenre(genre),
        );
      },
    );
  }

  Widget _buildGenreDetailView() {
    return Column(
      key: ValueKey(_selectedGenre!.id), // Ключ для анимации
      children: [
        _buildDetailHeader(),
        Expanded(
          child: _isLoadingBooks
              ? const Center(child: CircularProgressIndicator())
              : _books.isEmpty
              ? const Center(child: Text('Книг в этом жанре не найдено'))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _books.length,
            itemBuilder: (context, index) {
              return BookCardWidget(book: _books[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailHeader() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _resetGenre,
          ),
          Expanded(
            child: Text(
              _selectedGenre!.name,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // Распорка для центрирования
        ],
      ),
    );
  }
}

// Отдельный виджет для карточки жанра
class _GenreCard extends StatelessWidget {
  final Genre genre;
  final VoidCallback onTap;

  const _GenreCard({required this.genre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildGenreImage(genre),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: AutoSizeText(
                genre.name,
                textAlign: TextAlign.center,
                minFontSize: 12,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Логика отображения изображения для жанра
  Widget _buildGenreImage(Genre genre) {
    final Map<int, String> genreImages = {
      5: 'lib/assets/images/fantasy.png',
      2: 'lib/assets/images/detective.png',
      4: 'lib/assets/images/romance.png',
    };
    final asset = genreImages[genre.id] ?? 'lib/assets/images/logo.png';
    return Image.asset(
      asset,
      width: 82,
      height: 82,
      fit: BoxFit.contain,
    );
  }
}
