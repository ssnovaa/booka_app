// lib/screens/genres_screen.dart
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

import 'package:booka_app/core/network/api_client.dart';
import '../models/genre.dart';
import '../models/book.dart';
import '../services/catalog_service.dart';
import '../widgets/book_card.dart';

class GenresScreen extends StatefulWidget {
  final VoidCallback? onReturnToMain;

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
      final res = await CatalogService.fetchGenres(); // /genres — кэш на уровне сервиса
      setState(() {
        genres = res;
        selectedGenre = null;
        books = [];
      });
    } catch (e) {
      setState(() {
        error = 'Помилка завантаження жанрів: $e';
      });
    } finally {
      if (mounted) setState(() => isLoadingGenres = false);
    }
  }

  /// Отправляем genre по имени (как в CatalogScreen)
  Future<void> fetchBooksForGenre(Genre genre, {bool refresh = false}) async {
    setState(() {
      isLoadingBooks = true;
      error = null;
      books = [];
    });
    try {
      final params = <String, dynamic>{
        'genre': genre.name,
        'page': 1,
        'per_page': 20,
      };

      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.request,
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
            ? (data['data'] ?? data['items'] ?? data['books'] ?? [])
            : []);
        setState(() {
          books = items
              .map((e) => Book.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(() {
          error = 'Unexpected response: ${r.statusCode}';
        });
      }
    } on DioException catch (e) {
      setState(() {
        error = e.message ?? 'Network error';
      });
    } catch (e) {
      setState(() {
        error = 'Parsing error: $e';
      });
    } finally {
      if (mounted) setState(() => isLoadingBooks = false);
    }
  }

  // Back: если выбран жанр — сбрасываем выбор, иначе дергаем onReturnToMain
  Future<bool> _onWillPop() async {
    if (selectedGenre != null) {
      setState(() {
        selectedGenre = null;
        books = [];
      });
      return false;
    }
    if (widget.onReturnToMain != null) {
      widget.onReturnToMain!();
    }
    return false;
  }

  Future<void> _onPullToRefresh() async {
    if (selectedGenre == null) {
      await fetchGenres();
    } else {
      await fetchBooksForGenre(selectedGenre!, refresh: true); // жёсткий refresh
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: Builder(
          builder: (context) {
            if (isLoadingGenres && genres.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (error != null && genres.isEmpty) {
              return _ErrorPanel(
                message: error!,
                onRetry: fetchGenres,
              );
            }

            if (genres.isEmpty) {
              return RefreshIndicator(
                onRefresh: _onPullToRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    Center(child: Text('Жанрів не знайдено')),
                    SizedBox(height: 80),
                  ],
                ),
              );
            }

            // --- Экран жанров (без выбранного жанра) — строгие плитки
            if (selectedGenre == null) {
              return RefreshIndicator(
                onRefresh: _onPullToRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: genres.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.05,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        final genre = genres[index];
                        return _GenreTile(
                          genre: genre,
                          onTap: () async {
                            setState(() {
                              selectedGenre = genre;
                              books = [];
                            });
                            await fetchBooksForGenre(genre, refresh: true);
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
            }

            // --- Экран выбранного жанра: «пилюли» + список
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: genres.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 3.0,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final genre = genres[index];
                      final isSelected = selectedGenre?.id == genre.id;
                      return _GenrePill(
                        label: genre.name,
                        selected: isSelected,
                        onTap: () async {
                          setState(() {
                            selectedGenre = genre;
                            books = [];
                          });
                          await fetchBooksForGenre(genre, refresh: true);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _onPullToRefresh,
                    child: isLoadingBooks
                        ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                        : (error != null && books.isEmpty)
                        ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _ErrorPanel(
                          message: error ?? 'Помилка завантаження книг',
                          onRetry: () => fetchBooksForGenre(selectedGenre!, refresh: true),
                        ),
                      ],
                    )
                        : (books.isEmpty)
                        ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Center(child: Text('Книг не знайдено для цього жанру')),
                      ],
                    )
                        : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: BookCardWidget(book: book),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Строгая плитка жанра: без теней, с тонкой рамкой и подписью под изображением
class _GenreTile extends StatelessWidget {
  final Genre genre;
  final VoidCallback onTap;

  const _GenreTile({required this.genre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = cs.outline;
    final asset = _genreAsset(genre.id);

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AutoSizeText(
                genre.name,
                maxLines: 1,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
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
  }

  static String _genreAsset(int id) {
    switch (id) {
      case 5:
        return 'lib/assets/images/fantasy.png';
      case 2:
        return 'lib/assets/images/detective.png';
      case 4:
        return 'lib/assets/images/romance.png';
      default:
        return 'lib/assets/images/logo.png';
    }
  }
}

/// Строгая «пилюля» жанра: тонкая рамка, без тени/градиентов
class _GenrePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenrePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = selected ? cs.primary : cs.outline;            // контрастнее в дарке
    final bg = selected ? cs.primaryContainer : cs.surface;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;   // <— фикс читабельности

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: AutoSizeText(
            label,
            maxLines: 1,
            minFontSize: 10,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 100),
        Center(child: Text(message, textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        Align(
          child: FilledButton(
            onPressed: onRetry,
            child: const Text('Повторити'),
          ),
        ),
      ],
    );
  }
}
