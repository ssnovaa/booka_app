// lib/screens/book_detail_screen.dart
import 'dart:ui'; // для BackdropFilter (glass-ефект)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/constants.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/widgets/mini_player.dart';
import 'package:booka_app/widgets/simple_player_bottom_sheet.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/image_cache.dart';
import 'package:booka_app/widgets/booka_app_bar.dart'; // спільний AppBar з глобальною кнопкою теми

class BookDetailScreen extends StatefulWidget {
  final Book book;
  final Chapter? initialChapter;
  final int? initialPosition;
  final bool autoPlay;

  const BookDetailScreen({
    Key? key,
    required this.book,
    this.initialChapter,
    this.initialPosition,
    this.autoPlay = false,
  }) : super(key: key);

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  // Текущая "полная" книга (может обновиться после догрузки)
  late Book _book;

  // Главы
  List<Chapter> chapters = [];
  int selectedChapterIndex = 0;

  // Флаги загрузки/ошибок
  bool isLoading = true; // загрузка глав
  String? error;

  bool _playerInitialized = false;
  bool _autoStartPending = false;

  // Загрузка книги (если пришла урезанной)
  bool _bookLoading = false;
  String? _bookError;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _maybeLoadFullBook(); // подтягиваем недостающую информацию о книге
    fetchChapters();      // и параллельно тянем главы
  }

  // Проверяем, "урезан" ли объект книги
  bool _isSparse(Book b) {
    return (b.description == null || b.description!.trim().isEmpty) ||
        b.genres.isEmpty ||
        (b.reader == null || b.reader!.trim().isEmpty);
  }

  Future<void> _maybeLoadFullBook({bool refresh = false}) async {
    if (!_isSparse(_book) && !refresh) return;

    setState(() {
      _bookLoading = true;
      _bookError = null;
    });

    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
        maxStale: const Duration(hours: 24),
      );

      final resp = await ApiClient.i()
          .get('/abooks/${_book.id}', options: cacheOpts.toOptions())
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = resp.data;
        Map<String, dynamic> raw;
        if (data is Map && data['data'] is Map) {
          raw = Map<String, dynamic>.from(data['data']);
        } else if (data is Map<String, dynamic>) {
          raw = data;
        } else {
          throw Exception('Unexpected response');
        }

        final full = Book.fromJson(raw);
        setState(() {
          _book = full;
          _bookLoading = false;
        });
      } else {
        setState(() {
          _bookLoading = false;
          _bookError = 'Помилка завантаження книги: ${resp.statusCode}';
        });
      }
    } on DioException catch (e) {
      setState(() {
        _bookLoading = false;
        _bookError = 'Мережева помилка: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _bookLoading = false;
        _bookError = 'Помилка з’єднання: $e';
      });
    }
  }

  Future<void> fetchChapters({bool refresh = false}) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);

    try {
      // КЕШ: forceCache (звично) / refreshForceCache (pull-to-refresh), maxStale 24h
      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
        maxStale: const Duration(hours: 24),
      );

      final resp = await ApiClient.i()
          .get('/abooks/${_book.id}/chapters', options: cacheOpts.toOptions())
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = resp.data;
        final List<dynamic> items = (data is List)
            ? data
            : (data is Map<String, dynamic>
            ? (data['data'] ?? data['items'] ?? [])
            : []);

        final loadedChapters = items
            .map((item) => Chapter.fromJson(item as Map<String, dynamic>))
            .toList();

        int startIndex = 0;
        if (widget.initialChapter != null) {
          final ix =
          loadedChapters.indexWhere((c) => c.id == widget.initialChapter!.id);
          if (ix != -1) startIndex = ix;
        }

        setState(() {
          chapters = loadedChapters;
          selectedChapterIndex = startIndex;
          isLoading = false;
          _playerInitialized = false;
          _autoStartPending = true; // ініціалізуємо плеєр після побудови
        });
      } else {
        setState(() {
          error = 'Помилка завантаження розділів: ${resp.statusCode}';
          isLoading = false;
        });
        await audioProvider.pause();
      }
    } on DioException catch (e) {
      setState(() {
        error = 'Мережева помилка: ${e.message}';
        isLoading = false;
      });
      await audioProvider.pause();
    } catch (e) {
      setState(() {
        error = 'Помилка з’єднання: $e';
        isLoading = false;
      });
      await audioProvider.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_playerInitialized && !_autoStartPending && chapters.isNotEmpty) {
      _initAudioPlayer();
    }
  }

  @override
  void didUpdateWidget(covariant BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      _book = widget.book;
      _playerInitialized = false;
      _autoStartPending = true;
      _maybeLoadFullBook(refresh: true);
      fetchChapters();
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  // Привести относительный путь к абсолютному
  String _absUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final s = path.trim();
    return s.startsWith('http') ? s : fullResourceUrl(s);
  }

  void _initAudioPlayer() {
    if (_playerInitialized || chapters.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
      final user = Provider.of<UserNotifier>(context, listen: false).user;
      audio.userType = getUserType(user);

      final startIndex = selectedChapterIndex;

      final sameChapters = audio.currentChapter != null &&
          audio.chapters.length == chapters.length &&
          List.generate(chapters.length, (i) => chapters[i].id).join(',') ==
              List.generate(audio.chapters.length, (i) => audio.chapters[i].id)
                  .join(',');

      if (!sameChapters) {
        await audio.setChapters(
          chapters,
          book: _book,
          startIndex: startIndex,
          bookTitle: _book.title,
          artist: _book.author,
          coverUrl: _absUrl(_book.coverUrl),
        );
      }

      if (widget.initialPosition != null) {
        await audio.player.seek(
          Duration(seconds: widget.initialPosition!),
          index: startIndex,
        );
        if (widget.autoPlay) await audio.play();
      } else if (widget.initialChapter != null && widget.autoPlay) {
        await audio.player.seek(Duration.zero, index: startIndex);
        await audio.play();
      }

      if (mounted) {
        setState(() {
          _playerInitialized = true;
          _autoStartPending = false;
        });
      }
    });
  }

  Future<void> _onChapterSelected(Chapter chapter) async {
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index != -1) {
      setState(() => selectedChapterIndex = index);
      final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
      await audio.player.seek(Duration.zero, index: index);
      await audio.play();
    }
  }

  /// BG для плеєра: миниатюра, если есть, иначе обложка (всегда абсолютный URL)
  String? _resolveBgUrl(Book book) {
    // Попытка вычитать возможные альтернативные поля миниатюры
    try {
      final dynamic dyn = book;
      final String? thumb1 = dyn.thumbnailUrl as String?;
      if (thumb1 != null && thumb1.isNotEmpty) return _absUrl(thumb1);
    } catch (_) {}
    try {
      final dynamic dyn = book;
      final String? thumb2 = dyn.thumb as String?;
      if (thumb2 != null && thumb2.isNotEmpty) return _absUrl(thumb2);
    } catch (_) {}
    return _absUrl(book.coverUrl);
  }

  void _openFullPlayer() {
    if (chapters.isEmpty) return;
    final bgUrl = _resolveBgUrl(_book);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullPlayerBottomSheet(
        title: _book.title,
        author: _book.author,
        coverUrl: bgUrl, // ← миниатюра (если есть) или обложка
        chapters: chapters,
        selectedChapter: chapters[selectedChapterIndex],
        onChapterSelected: _onChapterSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = Provider.of<UserNotifier>(context).user;
    final userType = getUserType(user);

    // ==== Візуальні штрихи ====
    final size = MediaQuery.of(context).size;
    final coverHeight = size.height * 0.5;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    int memCacheHeight = (coverHeight * dpr).round();
    if (memCacheHeight > 2200) memCacheHeight = 2200;

    final double topGradientHeight = coverHeight + 120;

    final audio = Provider.of<AudioPlayerProvider>(context);
    final currentChapter = audio.currentChapter;

    // Отложенная инициализация плеера после загрузки глав
    if (!_playerInitialized && _autoStartPending && !isLoading && chapters.isNotEmpty) {
      _autoStartPending = false;
      _initAudioPlayer();
    }

    final coverUrlAbs = _absUrl(_book.coverUrl);

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : (error != null)
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => fetchChapters(refresh: true),
                child: const Text('Повторити'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      )
          : Stack(
        children: [
          // Топ-градієнтний фон (не перехоплює тачи)
          IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: topGradientHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.primary.withOpacity(0.18),
                      cs.primaryContainer.withOpacity(0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: () async {
              await _maybeLoadFullBook(refresh: true);
              await fetchChapters(refresh: true);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (coverUrlAbs.isNotEmpty)
                    Center(
                      child: Container(
                        // м’яка тінь навколо обкладинки
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withOpacity(0.25),
                              blurRadius: 40,
                              spreadRadius: 0,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: FractionallySizedBox(
                            widthFactor: 1.0,
                            child: CachedNetworkImage(
                              imageUrl: coverUrlAbs,
                              cacheManager:
                              BookaImageCacheManager.instance,
                              height: coverHeight,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => SizedBox(
                                height: coverHeight,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (_, __, ___) => SizedBox(
                                height: coverHeight,
                                child: const Icon(Icons.broken_image,
                                    size: 48),
                              ),
                              memCacheHeight: memCacheHeight,
                            ),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Название
                  Text(
                    _book.title.isNotEmpty ? _book.title : 'Без назви',
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Автор + Чтец
                  Row(
                    children: [
                      if (_book.author.trim().isNotEmpty)
                        Flexible(
                          child: Text(
                            _book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.85),
                            ),
                          ),
                        ),
                      if (_book.reader != null &&
                          _book.reader!.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Text('•'),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _book.reader!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.78),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Метадані (легка glass-картка)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_book.genres.isNotEmpty)
                              Text(
                                'Жанри: ${_book.genres.join(', ')}',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (_book.duration.isNotEmpty)
                              Text(
                                'Тривалість: ${_book.duration}',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (_book.series != null &&
                                _book.series!.isNotEmpty)
                              Text(
                                'Серія: ${_book.series}',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (_bookLoading) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Оновлення даних книги…'),
                                ],
                              ),
                            ],
                            if (_bookError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _bookError!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.redAccent),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if ((_book.description ?? '').trim().isNotEmpty)
                    Text(
                      _book.description!.trim(),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(height: 1.5),
                    ),

                  const SizedBox(height: 16),

                  if (userType == UserType.guest)
                    Text(
                      'Увійдіть або зареєструйтесь, щоб отримати доступ до інших розділів.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.primary),
                    ),
                  if (userType == UserType.free)
                    Text(
                      'Безкоштовний тариф відтворює з рекламою. Оформіть підписку, щоб слухати без реклами.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.tertiary),
                    ),
                ],
              ),
            ),
          ),

          // Міні-плеєр
          if (currentChapter != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayerWidget(
                chapter: currentChapter,
                bookTitle: _book.title,
                coverUrl: _resolveBgUrl(_book), // мініатюра або обкладинка
                onExpand: _openFullPlayer,
              ),
            ),
        ],
      ),
    );
  }
}
