import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/user.dart';
import '../providers/audio_player_provider.dart';
import '../user_notifier.dart';
import '../widgets/mini_player.dart';
import '../widgets/simple_player_bottom_sheet.dart';

class BookDetailScreen extends StatefulWidget {
  final Book book;
  final Chapter? initialChapter;
  final int? initialPosition;
  final bool autoPlay;

  const BookDetailScreen({
    super.key,
    required this.book,
    this.initialChapter,
    this.initialPosition,
    this.autoPlay = false,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  List<Chapter> chapters = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchChaptersAndInitPlayer());
  }

  Future<void> _fetchChaptersAndInitPlayer() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final uri = Uri.parse('$BASE_URL/abooks/${widget.book.id}/chapters');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data is List ? data : data['data'];
        final loadedChapters = items.map((item) => Chapter.fromJson(item)).toList();

        setState(() {
          chapters = loadedChapters;
          isLoading = false;
        });

        // ИСПРАВЛЕНИЕ: Вызываем новый метод setBook
        await context.read<AudioPlayerProvider>().setBook(
          widget.book,
          loadedChapters,
          startChapterId: widget.initialChapter?.id ?? 0,
          autoPlay: widget.autoPlay,
        );

        // ИСПРАВЛЕНИЕ: seek делаем после setBook
        if (widget.initialPosition != null) {
          await context.read<AudioPlayerProvider>().seek(Duration(seconds: widget.initialPosition!));
        }

      } else {
        throw Exception('Ошибка загрузки глав: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Ошибка: $e';
        isLoading = false;
      });
    }
  }

  void _onChapterSelected(Chapter chapter) async {
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index != -1) {
      await context.read<AudioPlayerProvider>().seekToChapter(index);
    }
  }

  void _openFullPlayer() {
    if (chapters.isEmpty) return;

    final audioProvider = context.read<AudioPlayerProvider>();
    final currentChapterFromProvider = audioProvider.currentChapter;
    if (currentChapterFromProvider == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullPlayerBottomSheet(
        title: widget.book.title,
        author: widget.book.author,
        chapters: chapters,
        selectedChapter: currentChapterFromProvider,
        onChapterSelected: _onChapterSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return _buildLoading();
    }
    if (error != null) {
      return _buildError();
    }
    return _buildContent();
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchChaptersAndInitPlayer,
              child: const Text('Повторить'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Назад', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final book = widget.book;
    final userType = context.watch<UserNotifier>().userType;
    final safePadding = MediaQuery.of(context).padding;

    int freeChaptersCount = (userType == UserType.free) ? 3 : chapters.length;
    if (userType == UserType.paid) freeChaptersCount = chapters.length;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, safePadding.top, 16, safePadding.bottom + 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const BackButton(color: Colors.white),
              const SizedBox(height: 16),
              if (book.coverUrl != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      book.coverUrl!,
                      fit: BoxFit.contain,
                      height: MediaQuery.of(context).size.height * 0.35,
                      loadingBuilder: (context, child, progress) {
                        return progress == null ? child : const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.broken_image, size: 48, color: Colors.grey);
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _buildBookInfo(context, book),
              const SizedBox(height: 24),
              if (book.description != null && book.description!.isNotEmpty)
                Text(
                  book.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 24),
              _buildAccessInfo(context, userType, freeChaptersCount),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Consumer<AudioPlayerProvider>(
            builder: (context, audio, child) {
              final currentChapter = audio.currentChapter;
              if (currentChapter != null && audio.currentBook?.id == widget.book.id) {
                return MiniPlayerWidget(
                  chapter: currentChapter,
                  bookTitle: widget.book.title,
                  onExpand: _openFullPlayer,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBookInfo(BuildContext context, Book book) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.genres.isNotEmpty)
            Text('Жанры: ${book.genres.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          if (book.duration.isNotEmpty)
            Text('Длительность: ${book.duration}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          if (book.series != null && book.series!.isNotEmpty)
            Text('Серия: ${book.series}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildAccessInfo(BuildContext context, UserType userType, int freeChaptersCount) {
    String? message;
    Color? color;

    if (userType == UserType.guest) {
      message = 'Войдите или зарегистрируйтесь, чтобы получить доступ к другим главам.';
      color = Colors.blueGrey[200];
    } else if (userType == UserType.free) {
      message = 'Доступно только $freeChaptersCount главы. Оформите подписку для полного доступа.';
      color = Colors.orange[200];
    }

    if (message == null) {
      return const SizedBox.shrink();
    }

    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    );
  }
}
