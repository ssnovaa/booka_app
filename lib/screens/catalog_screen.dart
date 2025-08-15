// lib/screens/catalog_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/models/genre.dart';
import 'package:booka_app/models/author.dart';
import 'package:booka_app/screens/book_detail_screen.dart';
import 'package:booka_app/user_notifier.dart';

import 'package:booka_app/widgets/last_books_widget.dart';
import 'package:booka_app/widgets/popular_books_widget.dart';
import 'package:booka_app/widgets/current_listen_card.dart';
import 'package:booka_app/widgets/book_card.dart';
import 'package:booka_app/widgets/catalog_filters.dart';
import 'package:booka_app/widgets/booka_app_bar.dart'; // общий AppBar с глобальным переключателем темы

/// Для отслеживания возврата с других экранов (обновление карточки)
final RouteObserver<ModalRoute<void>> routeObserver =
RouteObserver<ModalRoute<void>>();

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
  final TextEditingController searchController = TextEditingController();

  bool isLoading = false;
  String? error;

  late Future<Map<String, dynamic>?> profileFuture;

  // Чтобы пересобирать карточку прогресса по возврату на экран:
  Key currentListenCardKey = UniqueKey();

  /// Находим выбранный жанр по id из текущего списка жанров
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
    fetchFiltersAndBooks(); // первый прогон
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modal = ModalRoute.of(context);
    if (modal != null) routeObserver.subscribe(this, modal);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    searchController.dispose();
    super.dispose();
  }

  /// Когда вернулись со страницы книги — обновить карточку прогресса!
  @override
  void didPopNext() {
    setState(() {
      currentListenCardKey = UniqueKey();
    });
  }

  /// Попытка получить профиль через ApiClient (Dio). Возвращаем Map или null.
  /// 401 не считаем ошибкой — гость.
  Future<Map<String, dynamic>?> fetchUserProfile() async {
    try {
      final r = await ApiClient.i().get(
        '/profile',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(r.data as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
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
        return buildMainContent(snapshot.data);
      },
    );

    if (!widget.showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: bookaAppBar(
        actions: const [],
      ),
      body: content,
    );
  }

  Widget buildMainContent(Map<String, dynamic>? profileData) {
    final userNotifier = Provider.of<UserNotifier>(context, listen: false);
    final bool isAuth = userNotifier.isAuth;

    final headerWidgets = <Widget>[
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
          // важный момент — берём свежие данные из сети и обновляем кэш
          fetchBooks(refresh: true);
        },
        onAuthorChanged: (a) {
          setState(() => selectedAuthor = a);
          fetchBooks();
        },
        onSearch: fetchBooks,
      ),
    ];

    return Stack(
      children: [
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? Center(child: Text(error!))
            : RefreshIndicator(
          onRefresh: () =>
              fetchFiltersAndBooks(refresh: true), // форсим сеть
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: headerWidgets.length + books.length + 1,
            itemBuilder: (context, index) {
              if (index < headerWidgets.length) {
                return headerWidgets[index];
              }
              final bookIndex = index - headerWidgets.length;
              if (bookIndex < books.length) {
                return BookCardWidget(book: books[bookIndex]);
              }
              return const SizedBox(height: 24);
            },
          ),
        ),
      ],
    );
  }

  Future<void> fetchFiltersAndBooks({bool refresh = false}) async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final genreFuture = fetchGenres(refresh: refresh);
      final authorFuture = fetchAuthors(refresh: refresh);
      await Future.wait([genreFuture, authorFuture]);
      await fetchBooks(refresh: refresh);
    } catch (e) {
      setState(() {
        error = 'Ошибка загрузки фильтров: $e';
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<List<Genre>> fetchGenres({bool refresh = false}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
        maxStale: const Duration(hours: 24),
      );

      final r =
      await ApiClient.i().get('/genres', options: cacheOpts.toOptions());

      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is List
            ? data
            : (data is Map &&
            (data['data'] != null || data['items'] != null)
            ? (data['data'] ?? data['items'])
            : []);
        genres =
            raw.map((e) => Genre.fromJson(e as Map<String, dynamic>)).toList();
        return genres;
      }
      throw Exception('Ошибка загрузки жанров: ${r.statusCode}');
    } on DioException catch (e) {
      throw Exception('Ошибка загрузки жанров: ${e.message}');
    }
  }

  Future<List<Author>> fetchAuthors({bool refresh = false}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
        maxStale: const Duration(hours: 24),
      );

      final r =
      await ApiClient.i().get('/authors', options: cacheOpts.toOptions());

      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is List
            ? data
            : (data is Map &&
            (data['data'] != null || data['items'] != null)
            ? (data['data'] ?? data['items'])
            : []);
        authors =
            raw.map((e) => Author.fromJson(e as Map<String, dynamic>)).toList();
        return authors;
      }
      throw Exception('Ошибка загрузки авторов: ${r.statusCode}');
    } on DioException catch (e) {
      throw Exception('Ошибка загрузки авторов: ${e.message}');
    }
  }

  Future<void> fetchBooks({bool refresh = false}) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final Map<String, dynamic> params = {};
      if (searchController.text.isNotEmpty) {
        params['search'] = searchController.text;
      }
      // ВАЖНО: жанр отправляем как имя (как и в GenresScreen)
      if (selectedGenreId != null) {
        final g = selectedGenre;
        if (g != null) {
          params['genre'] = g.name; // <-- ключ, который ждёт бэкенд
        }
      }
      if (selectedAuthor != null) {
        params['author'] = selectedAuthor!.name;
      }

      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
        maxStale: const Duration(hours: 6),
      );

      final r = await ApiClient.i().get(
        '/abooks',
        queryParameters: params,
        options: cacheOpts.toOptions(),
      );

      if (r.statusCode == 200) {
        final data = r.data;
        final List<dynamic> items = data is List
            ? data
            : (data is Map<String, dynamic>
            ? (data['data'] ?? data['items'] ?? [])
            : []);
        books = items
            .map((item) => Book.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        setState(() => error = 'Ошибка загрузки: ${r.statusCode}');
      }
    } on DioException catch (e) {
      setState(() => error = 'Ошибка подключения: ${e.message}');
    } catch (e) {
      setState(() => error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void resetFilters() {
    setState(() {
      selectedGenreId = null;
      selectedAuthor = null;
      searchController.clear();
    });
    // после сброса — свежий запрос
    fetchBooks(refresh: true);
  }
}
