// lib/screens/genres_screen.dart
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:cached_network_image/cached_network_image.dart'; // ← добавлено

import 'package:booka_app/core/network/api_client.dart';
import '../models/genre.dart';
import '../models/book.dart';
import '../services/catalog_service.dart';
import '../widgets/book_card.dart';
import 'package:booka_app/widgets/loading_indicator.dart';
import '../core/network/image_cache.dart'; // спільний кешер обкладинок жанрів

// ⛑ Безопасные тексты ошибок
import 'package:booka_app/core/security/safe_errors.dart';

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

  final ScrollController _tilesScrollCtrl = ScrollController();
  final ScrollController _booksScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    fetchGenres();
  }

  @override
  void dispose() {
    _tilesScrollCtrl.dispose();
    _booksScrollCtrl.dispose();
    super.dispose();
  }

  /// Синхронный хэндлер для контейнера: если жанр выбран — сбрасываем и возвращаем true.
  bool handleBackSync({bool scrollToTop = true}) {
    if (selectedGenre != null) {
      setState(() {
        selectedGenre = null;
        books = [];
        error = null;
        isLoadingBooks = false;
      });
      if (scrollToTop && _tilesScrollCtrl.hasClients) {
        // не await — пусть анимация идет сама
        _tilesScrollCtrl.animateTo(
          0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return true;
    }
    return false;
  }

  /// Завантажуємо список жанрів (сервіс сам керує кешем)
  Future<void> fetchGenres() async {
    setState(() {
      isLoadingGenres = true;
      error = null;
    });
    try {
      final res = await CatalogService.fetchGenres(); // /genres — кеш на рівні сервісу
      setState(() {
        genres = res.where((g) => g.hasBooks).toList();
        selectedGenre = null;
        books = [];
      });
    } catch (e) {
      setState(() {
        error = safeErrorMessage(e, fallback: 'Не вдалося завантажити жанри');
      });
    } finally {
      if (mounted) setState(() => isLoadingGenres = false);
    }
  }

  /// Надсилаємо genre за ім'ям (як у CatalogScreen)
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
          books =
              items.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
        });
      } else {
        setState(() {
          error = safeHttpStatus('Не вдалося завантажити книги', r.statusCode);
        });
      }
    } on DioException catch (e) {
      setState(() {
        error = safeErrorMessage(e, fallback: 'Проблема мережі');
      });
    } catch (e) {
      setState(() {
        error = safeErrorMessage(e, fallback: 'Помилка обробки даних');
      });
    } finally {
      if (mounted) setState(() => isLoadingBooks = false);
    }
  }

  Future<void> _onPullToRefresh() async {
    if (selectedGenre == null) {
      await fetchGenres();
    } else {
      await fetchBooksForGenre(selectedGenre!, refresh: true);
      if (_booksScrollCtrl.hasClients) {
        _booksScrollCtrl.jumpTo(0.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // final cs = Theme.of(context).colorScheme; // не используется — можно оставить закомментированным

    return Scaffold(
      body: Builder(
        builder: (context) {
          if (isLoadingGenres && genres.isEmpty) {
            return const Center(child: LoadingIndicator());
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

          // --- плитка жанров с картинками (исходный экран выбора)
          if (selectedGenre == null) {
            return RefreshIndicator(
              onRefresh: _onPullToRefresh,
              child: SingleChildScrollView(
                controller: _tilesScrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: genres.length,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
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

          // --- выбранный жанр: ТОЛЬКО список книг
          return RefreshIndicator(
            onRefresh: _onPullToRefresh,
            child: isLoadingBooks
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: LoadingIndicator()),
              ],
            )
                : (error != null && books.isEmpty)
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _ErrorPanel(
                  message: error ?? 'Помилка завантаження книг',
                  onRetry: () =>
                      fetchBooksForGenre(selectedGenre!, refresh: true),
                ),
              ],
            )
                : (books.isEmpty)
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                Center(
                    child: Text(
                        'Книги не знайдено для цього жанру')),
              ],
            )
                : ListView.builder(
              controller: _booksScrollCtrl,
              padding:
              const EdgeInsets.symmetric(horizontal: 8),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BookCardWidget(book: book),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Строга плитка жанру: без тіней, з тонкою рамкою і підписом під зображенням
class _GenreTile extends StatelessWidget {
  final Genre genre;
  final VoidCallback onTap;

  const _GenreTile({required this.genre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = cs.outline;

    final asset = _genreAsset(genre.id);
    final url = genre.imageUrl; // ← URL с сервера, если задан

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
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.82,
                      heightFactor: 0.82,
                      child: _buildImage(url, asset),
                    ),
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

  Widget _buildImage(String? url, String asset) {
    if (url == null || url.isEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: BookaImageCacheManager.instance,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (ctx, _) => const Center(
        child: SizedBox(width: 22, height: 22, child: LoadingIndicator(size: 22)),
      ),
      errorWidget: (ctx, _, __) => Image.asset(
        asset,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
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

/// Строга «пілюля» жанру: тонка рамка, без тіні/градієнтів
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
    final border = selected ? cs.primary : cs.outline;
    final bg = selected ? cs.primaryContainer : cs.surface;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;

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