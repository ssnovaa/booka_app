import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/genre.dart';
import '../models/author.dart';
import 'book_detail_screen.dart';
import '../providers/audio_player_provider.dart';
import '../user_notifier.dart';
import '../theme_notifier.dart';
import '../widgets/last_books_widget.dart';
import '../widgets/popular_books_widget.dart';
import '../widgets/current_listen_card.dart';
import '../widgets/book_card.dart';
import '../widgets/catalog_filters.dart';
import '../widgets/booka_app_bar_title.dart';

// Для отслеживания возврата с других экранов (обновление карточки)
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

class CatalogScreen extends StatefulWidget {
  final bool showAppBar;
  final int? selectedGenreId;

  // Добавлено const
  const CatalogScreen({
    super.key,
    this.showAppBar = true,
    this.selectedGenreId,
  });

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> with RouteAware {
  List<Book> books = [];
  List<Genre> genres = [];
  List<Author> authors = [];
  int? selectedGenreId;
  Author? selectedAuthor;
  final TextEditingController searchController = TextEditingController();

  bool isLoading = false;
  String? error;

  // Чтобы пересобирать карточку прогресса по возврату на экран:
  Key currentListenCardKey = UniqueKey();

  Genre? get selectedGenre {
    if (selectedGenreId == null) return null;
    // Используем firstWhereOrNull для безопасности и краткости
    return genres.cast<Genre?>().firstWhere((g) => g?.id == selectedGenreId, orElse: () => null);
  }

  @override
  void initState() {
    super.initState();
    selectedGenreId = widget.selectedGenreId;
    fetchFiltersAndBooks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Подписываемся на RouteObserver для автоматического обновления карточки
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    // Отписываемся от RouteObserver
    routeObserver.unsubscribe(this);
    searchController.dispose();
    super.dispose();
  }

  // Когда вернулись со страницы книги — обновить карточку прогресса!
  @override
  void didPopNext() {
    setState(() {
      currentListenCardKey = UniqueKey();
    });
  }

  /// Реализация кнопки "Продолжить"
  void _continueListening() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('current_listen');
    if (jsonStr == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет сохранённой книги для продолжения.')),
      );
      return;
    }

    try {
      final data = json.decode(jsonStr);
      final bookJson = data['book'] as Map<String, dynamic>;
      final chapterJson = data['chapter'] as Map<String, dynamic>;
      final position = data['position'] ?? 0;

      final book = Book.fromJson(bookJson);
      // ИСПРАВЛЕНИЕ: передаем объект Book, а не Map
      final chapter = Chapter.fromJson(chapterJson, book: book);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: book,
            initialChapter: chapter,
            initialPosition: position,
            autoPlay: true,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при продолжении: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) {
      return _buildMainContent();
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: const BookaAppBarTitle(),
        actions: [
          Consumer<ThemeNotifier>(
            builder: (context, themeNotifier, _) => IconButton(
              icon: Icon(themeNotifier.isDark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined),
              tooltip: 'Сменить тему',
              onPressed: () => themeNotifier.toggleTheme(),
            ),
          ),
          const SizedBox(width: 15),
        ],
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    final bool isAuth = context.watch<UserNotifier>().isAuth;

    if (isLoading && books.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Ошибка: $error', textAlign: TextAlign.center),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchBooks,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          LastBooksWidget(books: books),
          if (isAuth)
            CurrentListenCard(
              key: currentListenCardKey,
              onContinue: _continueListening,
            ),
          PopularBooksWidget(books: books),
          CatalogFilters(
            genres: genres,
            authors: authors,
            selectedGenre: selectedGenre,
            selectedAuthor: selectedAuthor,
            searchController: searchController,
            onReset: resetFilters,
            onGenreChanged: (Genre? g) {
              setState(() => selectedGenreId = g?.id);
              fetchBooks();
            },
            onAuthorChanged: (a) {
              setState(() => selectedAuthor = a);
              fetchBooks();
            },
            onSearch: fetchBooks,
          ),
          ...books.map((book) => BookCardWidget(book: book)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> fetchFiltersAndBooks() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      await Future.wait([
        fetchGenres(),
        fetchAuthors(),
      ]);
      await fetchBooks();
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Ошибка загрузки данных: $e');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> fetchGenres() async {
    try {
      final response = await http.get(Uri.parse('$BASE_URL/genres'));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (mounted) {
          setState(() {
            genres = data.map((e) => Genre.fromJson(e)).toList();
          });
        }
      } else {
        throw Exception('Ошибка загрузки жанров');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> fetchAuthors() async {
    try {
      final response = await http.get(Uri.parse('$BASE_URL/authors'));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (mounted) {
          setState(() {
            authors = data.map((e) => Author.fromJson(e)).toList();
          });
        }
      } else {
        throw Exception('Ошибка загрузки авторов');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> fetchBooks() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        error = null;
      });
    }

    try {
      final Map<String, String> params = {};
      if (searchController.text.isNotEmpty) {
        params['search'] = searchController.text;
      }
      if (selectedGenreId != null) {
        params['genre_id'] = selectedGenreId.toString();
      }
      if (selectedAuthor != null) {
        params['author'] = selectedAuthor!.name;
      }

      final uri = Uri.parse('$BASE_URL/abooks').replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri);

      if (mounted) {
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data is List ? data : data['data'];
          setState(() {
            books = items.map((item) => Book.fromJson(item)).toList();
          });
        } else {
          setState(() => error = 'Ошибка загрузки книг: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Ошибка подключения: $e');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void resetFilters() {
    setState(() {
      selectedGenreId = null;
      selectedAuthor = null;
      searchController.clear();
    });
    fetchBooks();
  }
}
