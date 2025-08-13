import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../widgets/mini_player.dart';
import '../widgets/simple_player_bottom_sheet.dart';
import 'package:provider/provider.dart';
import '../user_notifier.dart';
import '../models/user.dart';
import '../providers/audio_player_provider.dart';

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
  final ScrollController _scrollController = ScrollController();

  bool _playerInitialized = false;
  bool _autoStartPending = false;

  @override
  void initState() {
    super.initState();
    fetchChapters();
  }

  Future<void> fetchChapters() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final uri = Uri.parse('$BASE_URL/abooks/${widget.book.id}/chapters');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data is List ? data : data['data'];
        final loadedChapters = items.map((item) => Chapter.fromJson(item)).toList();

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

        // Не инициализируем аудиоплеер здесь, делаем это после build (см. didChangeDependencies)
      } else {
        setState(() {
          error = 'Ошибка загрузки глав: ${response.statusCode}';
          isLoading = false;
        });
        Provider.of<AudioPlayerProvider>(context, listen: false).pause();
      }
    } catch (e) {
      setState(() {
        error = 'Ошибка подключения: $e';
        isLoading = false;
      });
      Provider.of<AudioPlayerProvider>(context, listen: false).pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Пытаемся инициализировать плеер после загрузки глав и только один раз
    if (!_playerInitialized && !_autoStartPending && chapters.isNotEmpty) {
      _initAudioPlayer();
    }
  }

  @override
  void didUpdateWidget(covariant BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если книга изменилась, сбрасываем флаги
    if (oldWidget.book.id != widget.book.id) {
      _playerInitialized = false;
      _autoStartPending = true;
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

      int startIndex = selectedChapterIndex;
      bool sameChapters = audio.currentChapter != null &&
          audio.chapters.length == chapters.length &&
          List.generate(chapters.length, (i) => chapters[i].id).join(',') ==
              List.generate(audio.chapters.length, (i) => audio.chapters[i].id).join(',');

      if (!sameChapters) {
        await audio.setChapters(
          chapters,
          book: widget.book, // <---- ОБЯЗАТЕЛЬНО передаём текущую книгу!
          startIndex: startIndex,
          bookTitle: widget.book.title,
          artist: widget.book.author,
          coverUrl: widget.book.coverUrl,
        );
      }

      // --- Позиция и автозапуск ---
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

      setState(() {
        _playerInitialized = true;
        _autoStartPending = false;
      });
    });
  }

  void _onChapterSelected(Chapter chapter) async {
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index != -1) {
      setState(() {
        selectedChapterIndex = index;
      });
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
    final book = widget.book;
    final user = Provider.of<UserNotifier>(context).user;
    final userType = getUserType(user);

    int freeChaptersCount = 1;
    if (userType == UserType.free) freeChaptersCount = 3;
    if (userType == UserType.paid) freeChaptersCount = chapters.length;

    final EdgeInsets safePadding = MediaQuery.of(context).padding;

    final audio = Provider.of<AudioPlayerProvider>(context);
    final currentChapter = audio.currentChapter;

    // После загрузки глав и первой отрисовки — инициализация плеера
    if (!_playerInitialized && _autoStartPending && !isLoading && chapters.isNotEmpty) {
      _autoStartPending = false;
      _initAudioPlayer();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: fetchChapters,
              child: const Text('Повторить'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[850],
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Назад'),
            ),
          ],
        ),
      )
          : Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, safePadding.top + 16, 16, safePadding.bottom + 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButton(color: Colors.white),
                if (book.coverUrl != null)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FractionallySizedBox(
                        widthFactor: 1.0,
                        child: Image.network(
                          book.coverUrl!,
                          fit: BoxFit.contain,
                          height: MediaQuery.of(context).size.height * 0.35,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (book.genres.isNotEmpty)
                        Text('Жанры: ${book.genres.join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white)),
                      if (book.duration.isNotEmpty)
                        Text('Длительность: ${book.duration}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white)),
                      if (book.series != null && book.series!.isNotEmpty)
                        Text('Серия: ${book.series}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (book.description != null && book.description!.isNotEmpty)
                  Text(
                    book.description!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      height: 1.5,
                    ),
                  ),
                const SizedBox(height: 16),
                if (userType == UserType.guest)
                  Text(
                    'Войдите или зарегистрируйтесь, чтобы получить доступ к другим главам.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey[100]),
                  ),
                if (userType == UserType.free)
                  Text(
                    'Доступно только $freeChaptersCount главы. Оформите подписку для полного доступа.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange[100]),
                  ),
              ],
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
