import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/genre.dart';
import '../models/author.dart';
import 'login_screen.dart';
import 'book_detail_screen.dart';
import 'profile_screen.dart';
import 'package:provider/provider.dart';
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
  TextEditingController searchController = TextEditingController();

  bool isLoading = false;
  String? error;

  late Future<Map<String, dynamic>?> profileFuture;

  // Чтобы пересобирать карточку прогресса по возврату на экран:
  Key currentListenCardKey = UniqueKey();

  Genre? get selectedGenre {
    if (selectedGenreId == null) return null;
    for (final g in genres) {
      if (g.id == selectedGenreId) return g;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    selectedGenreId = widget.selectedGenreId;
    profileFuture = fetchUserProfile();
    fetchFiltersAndBooks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Подписываемся на RouteObserver для автоматического обновления карточки
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    // Отписываемся от RouteObserver
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Когда вернулись со страницы книги — обновить карточку прогресса!
  @override
  void didPopNext() {
    setState(() {
      currentListenCardKey = UniqueKey();
    });
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, dynamic>?> fetchUserProfile() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    final url = Uri.parse('$BASE_URL/profile');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      return null;
    }
  }

  /// Реализация кнопки "Продолжить"
  void _continueListening() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('current_listen');
    if (jsonStr == null) {
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
      final chapter = Chapter.fromJson(chapterJson, book: bookJson);

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
    final content = FutureBuilder<Map<String, dynamic>?>(
      future: profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return buildMainContent(null);
        }
        return buildMainContent(snapshot.data);
      },
    );

    if (!widget.showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: const BookaAppBarTitle(),
        actions: [
          Consumer<ThemeNotifier>(
            builder: (context, themeNotifier, _) => IconButton(
              icon: Icon(themeNotifier.isDark
                  ? Icons.dark_mode
                  : Icons.light_mode),
              tooltip: 'Сменить тему',
              onPressed: () => themeNotifier.toggleTheme(),
            ),
          ),
          const SizedBox(width: 15),
        ],
      ),
      body: content,
    );
  }

  Widget buildMainContent(Map<String, dynamic>? data) {
    // Проверяем авторизацию через UserNotifier (контекст провайдера)
    final userNotifier = Provider.of<UserNotifier>(context, listen: false);
    final bool isAuth = userNotifier.isAuth;

    return Stack(
      children: [
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? Center(child: Text(error!))
            : RefreshIndicator(
          onRefresh: fetchBooks,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              LastBooksWidget(books: books),
              // Обновление карточки через key гарантирует, что при возврате всегда свежие данные!
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
        ),
      ],
    );
  }

  Future<void> fetchFiltersAndBooks() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final genreFuture = fetchGenres();
      final authorFuture = fetchAuthors();
      await Future.wait([genreFuture, authorFuture]);
      await fetchBooks();
    } catch (e) {
      error = 'Ошибка загрузки фильтров: $e';
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<List<Genre>> fetchGenres() async {
    final response = await http.get(Uri.parse('$BASE_URL/genres'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      genres = data.map((e) => Genre.fromJson(e)).toList();
      return genres;
    } else {
      throw Exception('Ошибка загрузки жанров');
    }
  }

  Future<List<Author>> fetchAuthors() async {
    final response = await http.get(Uri.parse('$BASE_URL/authors'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      authors = data.map((e) => Author.fromJson(e)).toList();
      return authors;
    } else {
      throw Exception('Ошибка загрузки авторов');
    }
  }

  Future<void> fetchBooks() async {
    setState(() {
      isLoading = true;
      error = null;
    });

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

      final uri = Uri.parse('$BASE_URL/abooks').replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data is List ? data : data['data'];
        books = items.map((item) => Book.fromJson(item)).toList();
      } else {
        error = 'Ошибка загрузки: ${response.statusCode}';
      }
    } catch (e) {
      error = 'Ошибка подключения: $e';
    } finally {
      setState(() => isLoading = false);
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
