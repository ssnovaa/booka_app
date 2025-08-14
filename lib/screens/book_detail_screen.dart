// lib/screens/book_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/widgets/mini_player.dart';
import 'package:booka_app/widgets/simple_player_bottom_sheet.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/image_cache.dart';
import 'package:booka_app/widgets/booka_app_bar.dart'; // общий AppBar с глобальной кнопкой темы

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
  List<Chapter> chapters = [];
  int selectedChapterIndex = 0;
  bool isLoading = true;
  String? error;

  bool _playerInitialized = false;
  bool _autoStartPending = false;

  @override
  void initState() {
    super.initState();
    fetchChapters(); // первый заход: читаем из кэша при наличии
  }

  Future<void> fetchChapters({bool refresh = false}) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);

    try {
      // КЭШ: forceCache (обычно) / refreshForceCache (refresh), maxStale 24h
      final cacheOpts = ApiClient.cacheOptions(
        policy: refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
        maxStale: const Duration(hours: 24),
      );

      final resp = await ApiClient.i()
          .get('/abooks/${widget.book.id}/chapters', options: cacheOpts.toOptions())
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = resp.data;
        final List<dynamic> items =
        (data is List) ? data : (data is Map<String, dynamic> ? (data['data'] ?? data['items'] ?? []) : []);

        final loadedChapters =
        items.map((item) => Chapter.fromJson(item as Map<String, dynamic>)).toList();

        int startIndex = 0;
        if (widget.initialChapter != null) {
          final ix = loadedChapters.indexWhere((c) => c.id == widget.initialChapter!.id);
          if (ix != -1) startIndex = ix;
        }

        setState(() {
          chapters = loadedChapters;
          selectedChapterIndex = startIndex;
          isLoading = false;
          _playerInitialized = false;
          _autoStartPending = true;
        });
      } else {
        setState(() {
          error = 'Ошибка загрузки глав: ${resp.statusCode}';
          isLoading = false;
        });
        await audioProvider.pause();
      }
    } on DioException catch (e) {
      setState(() {
        error = 'Сетевая ошибка: ${e.message}';
        isLoading = false;
      });
      await audioProvider.pause();
    } catch (e) {
      setState(() {
        error = 'Ошибка подключения: $e';
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
      _playerInitialized = false;
      _autoStartPending = true;
      fetchChapters();
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
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
              List.generate(audio.chapters.length, (i) => audio.chapters[i].id).join(',');

      if (!sameChapters) {
        await audio.setChapters(
          chapters,
          book: widget.book,
          startIndex: startIndex,
          bookTitle: widget.book.title,
          artist: widget.book.author,
          coverUrl: widget.book.coverUrl,
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

  void _onChapterSelected(Chapter chapter) async {
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index != -1) {
      setState(() => selectedChapterIndex = index);
      final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
      await audio.player.seek(Duration.zero, index: index);
      await audio.play();
    }
  }

  void _openFullPlayer() {
    if (chapters.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullPlayerBottomSheet(
        title: widget.book.title,
        author: widget.book.author,
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

    final book = widget.book;
    final user = Provider.of<UserNotifier>(context).user;
    final userType = getUserType(user);

    int freeChaptersCount = 1;
    if (userType == UserType.free) freeChaptersCount = 3;
    if (userType == UserType.paid) freeChaptersCount = chapters.length;

    final coverHeight = MediaQuery.of(context).size.height * 0.35;
    final audio = Provider.of<AudioPlayerProvider>(context);
    final currentChapter = audio.currentChapter;

    if (!_playerInitialized && _autoStartPending && !isLoading && chapters.isNotEmpty) {
      _autoStartPending = false;
      _initAudioPlayer();
    }

    return Scaffold(
      appBar: bookaAppBar(
        // можно добавить свои действия, глобальная кнопка темы уже есть
        actions: const [],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
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
          RefreshIndicator(
            onRefresh: () => fetchChapters(refresh: true),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (book.coverUrl != null && book.coverUrl!.isNotEmpty)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FractionallySizedBox(
                          widthFactor: 1.0,
                          child: CachedNetworkImage(
                            imageUrl: book.coverUrl!,
                            cacheManager: BookaImageCacheManager.instance,
                            height: coverHeight,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => SizedBox(
                              height: coverHeight,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (_, __, ___) => SizedBox(
                              height: coverHeight,
                              child: const Icon(Icons.broken_image, size: 48),
                            ),
                            memCacheHeight: (coverHeight * MediaQuery.of(context).devicePixelRatio).round(),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Метаданные
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (book.genres.isNotEmpty)
                          Text(
                            'Жанри: ${book.genres.join(', ')}',
                            style: theme.textTheme.bodySmall,
                          ),
                        if (book.duration.isNotEmpty)
                          Text(
                            'Тривалість: ${book.duration}',
                            style: theme.textTheme.bodySmall,
                          ),
                        if (book.series != null && book.series!.isNotEmpty)
                          Text(
                            'Серія: ${book.series}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (book.description != null && book.description!.isNotEmpty)
                    Text(
                      book.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),

                  const SizedBox(height: 16),

                  if (userType == UserType.guest)
                    Text(
                      'Увійдіть або зареєструйтесь, щоб отримати доступ до інших розділів.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                    ),
                  if (userType == UserType.free)
                    Text(
                      'Доступно лише $freeChaptersCount розділи. Оформіть підписку для повного доступу.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary),
                    ),
                ],
              ),
            ),
          ),

          if (currentChapter != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayerWidget(
                chapter: currentChapter,
                bookTitle: widget.book.title,
                onExpand: _openFullPlayer,
              ),
            ),
        ],
      ),
    );
  }
}
