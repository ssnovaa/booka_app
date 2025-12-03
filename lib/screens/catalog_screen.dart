// lib/screens/catalog_screen.dart
import 'dart:convert';
import 'dart:async'; // ←

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // compute (парсинг поза UI ізолятом)
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
import 'package:booka_app/widgets/booka_app_bar.dart';

// ⬇️ провайдер плеєра
import 'package:booka_app/providers/audio_player_provider.dart';

// ⬇️ єдиний репозиторій профілю (single-flight + TTL)
import 'package:booka_app/repositories/profile_repository.dart';

// ⬇️ наш Lottie-лоадер (замість стандартного бублика)
import 'package:booka_app/widgets/loading_indicator.dart';

// ⬇️ санітизатор повідомлень про помилки (НЕ показуємо сирі тексти/URL/коди)
import 'package:booka_app/core/security/safe_errors.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
RouteObserver<ModalRoute<void>>();

/// ===== Парсинг поза головним ізолятом (прискорює перший рендер при великих списках) =====
List<Book> _parseBooksOffMain(List<dynamic> items) =>
    items.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();

List<Genre> _parseGenresOffMain(List raw) =>
    raw.map((e) => Genre.fromJson(e as Map<String, dynamic>)).toList();

List<Author> _parseAuthorsOffMain(List raw) =>
    raw.map((e) => Author.fromJson(e as Map<String, dynamic>)).toList();

class CatalogScreen extends StatefulWidget {
  final bool showAppBar;
  final int? selectedGenreId;

  const CatalogScreen({
    super.key,
    this.showAppBar = true,
    this.selectedGenreId,
  });

  @override
  State<CatalogScreen> createState() => CatalogScreenState();
}

class CatalogScreenState extends State<CatalogScreen> with RouteAware {
  List<Book> books = [];
  List<Genre> genres = [];
  List<Author> authors = [];
  int? selectedGenreId;
  Author? selectedAuthor;
  final TextEditingController searchController = TextEditingController();

  bool isLoading = false;
  String? error;

  // Замість прямого GET /profile — «прогрів» через репозиторій (результат у UI не використовується)
  late Future<void> profileFuture;

  Key currentListenCardKey = UniqueKey();

  Genre? get selectedGenre {
    if (selectedGenreId == null) return null;
    for (final g in genres) {
      if (g.id == selectedGenreId) return g;
    }
    return null;
  }

  /// Фільтри активні, коли обрано жанр або автора
  bool get filtersActive => selectedGenreId != null || selectedAuthor != null;

  @override
  void initState() {
    super.initState();
    selectedGenreId = widget.selectedGenreId;

    // Профіль «прогріваємо» одразу — через репозиторій (single-flight + TTL)
    profileFuture = _warmupProfile();

    // Важкі завантаження — після першого кадру, щоб не блокувати старт
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fetchFiltersAndBooks();
    });
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

  @override
  void didPopNext() {
    setState(() {
      currentListenCardKey = UniqueKey();
    });
  }

  /// Одноразове фонове завантаження профілю через репозиторій (без прямого /profile)
  Future<void> _warmupProfile() async {
    try {
      await ProfileRepository.I.load(debugTag: 'CatalogScreen.init');
    } catch (_) {
      // тихо ігноруємо: екран каталогу не залежить від профілю для рендера
    }
  }

  /// «Продовжити прослуховування»
  /// Локал-first: 1) миттєво готуємо з локалі і переходимо, 2) мережа — у фоні.
  /// Якщо локалі немає: пробуємо сервер, інакше — prefs.
  void _continueListening() async {
    final audio = context.read<AudioPlayerProvider>();

    // 1) Швидка локальна підготовка без мережі
    await audio.ensurePrepared();
    if (audio.currentBook != null && audio.currentChapter != null) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: audio.currentBook!,
            initialChapter: audio.currentChapter!,
            initialPosition: audio.position.inSeconds,
            autoPlay: true,
          ),
        ),
      );
      // 2) Статистика/резерв — у фоні
      // ignore: discarded_futures
      unawaited(audio.hydrateFromServerIfAvailable());
      return;
    }

    // 3) Локалі немає → спробуємо сервер
    final ok = await audio.hydrateFromServerIfAvailable();
    if (ok && audio.currentBook != null && audio.currentChapter != null) {
      await audio.ensurePrepared();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: audio.currentBook!,
            initialChapter: audio.currentChapter!,
            initialPosition: audio.position.inSeconds,
            autoPlay: true,
          ),
        ),
      );
      return;
    }

    // 4) Fallback: читаємо локальні prefs
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('current_listen');

      if (jsonStr == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Немає збереженої книги для продовження.')),
        );
        return;
      }

      final data = json.decode(jsonStr);
      final bookJson = data['book'] as Map<String, dynamic>;
      final chapterJson = data['chapter'] as Map<String, dynamic>;
      final rawPos = data['position'] ?? 0;
      final position = rawPos is int ? rawPos : int.tryParse('$rawPos') ?? 0;

      final book = Book.fromJson(bookJson);
      final chapter = Chapter.fromJson(chapterJson, book: bookJson);

      if (!mounted) return;
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
      if (!mounted) return;
      // ❗ Санітизуємо повідомлення
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<void>(
      future: profileFuture, // просто чекаємо прогріву профілю (без даних)
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 🔄 Наш глобальний Lottie-індикатор замість стандартного бублика
          return const Center(child: LoadingIndicator());
        }
        return buildMainContent();
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

  // === ДОДАТКОВЕ: «прозора плитка» + трохи ширше ===
  Widget _tile(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surface.withOpacity(0.28), // напівпрозора підкладка
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(0.12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }

  // обгортка для звичайних елементів — стандартна ширина
  Widget _padNormal(Widget child) =>
      Padding(padding: const EdgeInsets.all(8), child: child);

  Widget buildMainContent() {
    final userNotifier = Provider.of<UserNotifier>(context, listen: false);
    final bool isAuth = userNotifier.isAuth;

    // Коли фільтри активні — залишаємо тільки панель фільтрів.
    final List<Widget> headerWidgets = filtersActive
        ? <Widget>[
      _padNormal(
        CatalogFilters(
          genres: genres,
          authors: authors,
          selectedGenre: selectedGenre,
          selectedAuthor: selectedAuthor,
          searchController: searchController,
          onReset: resetFilters,
          onGenreChanged: (Genre? g) {
            setState(() => selectedGenreId = g?.id);
            fetchBooks(refresh: true);
          },
          onAuthorChanged: (a) {
            setState(() => selectedAuthor = a);
            fetchBooks();
          },
          onSearch: fetchBooks,
        ),
      ),
    ]
        : <Widget>[
      _tile(context, LastBooksWidget(books: books)),
      if (isAuth)
        CurrentListenCard(
          key: currentListenCardKey,
          onContinue: _continueListening,
        ),
      _tile(context, PopularBooksWidget(books: books)),
      _padNormal(
        CatalogFilters(
          genres: genres,
          authors: authors,
          selectedGenre: selectedGenre,
          selectedAuthor: selectedAuthor,
          searchController: searchController,
          onReset: resetFilters,
          onGenreChanged: (Genre? g) {
            setState(() => selectedGenreId = g?.id);
            fetchBooks(refresh: true);
          },
          onAuthorChanged: (a) {
            setState(() => selectedAuthor = a);
            fetchBooks();
          },
          onSearch: fetchBooks,
        ),
      ),
    ];

    return Stack(
      children: [
        isLoading
        // 🔄 Тут також показуємо Lottie, поки тягнемо книги/фільтри
            ? const Center(child: LoadingIndicator())
            : error != null
            ? Center(child: Text(error!))
            : RefreshIndicator(
          onRefresh: () async {
            // тягнемо все + освіжаємо картку current_listen
            setState(() {
              profileFuture = _warmupProfile();
              currentListenCardKey = UniqueKey();
            });
            await fetchFiltersAndBooks(refresh: true);
          },
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: headerWidgets.length + books.length + 1,
            itemBuilder: (context, index) {
              if (index < headerWidgets.length) {
                return headerWidgets[index];
              }
              final bookIndex = index - headerWidgets.length;
              if (bookIndex < books.length) {
                return _padNormal(
                    BookCardWidget(book: books[bookIndex]));
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
      // ❗ Санітизуємо повідомлення замість '...: $e'
      setState(() {
        error = safeErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<List<Genre>> fetchGenres({bool refresh = false}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy:
        refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
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
        final parsed = await compute(_parseGenresOffMain, raw);
        genres = parsed.where((g) => g.hasBooks).toList();
        return genres;
      }
      // Не формуємо «говорящі» Exception з деталями — кидаємо DioException для санітайзера
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        type: DioExceptionType.badResponse,
      );
    } on DioException {
      rethrow;
    }
  }

  Future<List<Author>> fetchAuthors({bool refresh = false}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy:
        refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
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
        authors = await compute(_parseAuthorsOffMain, raw);
        return authors;
      }
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        type: DioExceptionType.badResponse,
      );
    } on DioException {
      rethrow;
    }
  }

  /// Витягуємо «оцінку популярності» з сирого JSON-книги.
  /// Набір ключів підібрано з запасом, щоб не падати, якщо API змінюється.
  double _extractPopularity(dynamic item) {
    if (item is! Map<String, dynamic>) return 0;

    num? _asNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      final s = '$v'.trim();
      return num.tryParse(s);
    }

    // Перевіряємо кілька можливих полів
    const keys = <String>[
      'popularity',
      'popular',
      'popularity_score',
      'score',
      'plays',
      'play_count',
      'listens',
      'listeners',
      'views',
      'downloads',
      'favorites',
      'likes',
      'hearts',
      'stars',
      'rating',
      'rank',
    ];

    for (final k in keys) {
      if (item.containsKey(k)) {
        final v = _asNum(item[k]);
        if (v != null) return v.toDouble();
      }
    }

    // Іноді буває вкладений обʼєкт статистики
    final stats = item['stats'];
    if (stats is Map<String, dynamic>) {
      const statKeys = <String>[
        'popularity',
        'score',
        'plays',
        'play_count',
        'listens',
        'listeners',
        'favorites',
        'likes',
        'rating',
      ];
      for (final k in statKeys) {
        final v = _asNum(stats[k]);
        if (v != null) return v.toDouble();
      }
    }

    return 0;
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
      if (selectedGenreId != null) {
        final g = selectedGenre;
        if (g != null) {
          params['genre'] = g.name;
        }
      }
      if (selectedAuthor != null) {
        params['author'] = selectedAuthor!.name;
      }

      // При активних фільтрах — просимо у API сортування за популярністю (якщо підтримує)
      if (filtersActive) {
        params['sort'] = 'popular';
        params['order'] = 'desc';
      }

      final cacheOpts = ApiClient.cacheOptions(
        policy:
        refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
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

        // Клієнтське сортування на випадок, якщо сервер не відсортував.
        if (filtersActive) {
          items.sort((a, b) =>
              _extractPopularity(b).compareTo(_extractPopularity(a)));
        }

        books = await compute(_parseBooksOffMain, items);
      } else {
        // Кидаємо DioException і обробляємо в catch із санітизацією
        throw DioException(
          requestOptions: r.requestOptions,
          response: r,
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => error = safeErrorMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => error = safeErrorMessage(e));
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
    fetchBooks(refresh: true);
  }
}
