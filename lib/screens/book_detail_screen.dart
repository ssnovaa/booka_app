// lib/screens/book_detail_screen.dart
// ПОЛНЫЙ ФАЙЛ БЕЗ СОКРАЩЕНИЙ

import 'dart:developer' as developer;
import 'dart:ui'; // для BackdropFilter (glass-ефект)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/widgets/loading_indicator.dart';
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
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/screens/login_screen.dart'; // ⬅️ для переходу на екран логіну

// ⬇️ форматування тривалості (години і хвилини)
import 'package:booka_app/core/utils/duration_format.dart';

// ❗ Санітизація повідомлень про помилки
import 'package:booka_app/core/security/safe_errors.dart';

// 🔽 Висота банерної реклами (AdSize.banner.height)
const double _kAdH = 50.0;

class BookDetailScreen extends StatefulWidget {
  final Book book;
  final Chapter? initialChapter;
  final int? initialPosition;

  const BookDetailScreen({
    super.key,
    required this.book,
    this.initialChapter,
    this.initialPosition,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  // Локальний логер для розслідування ініціалізації плеєра
  void _logPlayer(String msg) {
    // Логувати завжди, щоби відловлювати сценарії на реальних пристроях
    developer.log(msg, name: 'BOOK_DETAIL');
    debugPrint('[BOOK_DETAIL] $msg');
  }

  // Поточна «повна» книга (може оновитися після довантаження)
  late Book _book;

  // Розділи
  List<Chapter> chapters = [];
  int selectedChapterIndex = 0;

  // Прапорці завантаження/помилок
  bool isLoading = true; // завантаження розділів
  String? error;

  bool _playerInitialized = false;
  bool _initialPositionApplied = false;

  // Завантаження книги (якщо прийшла урізаною)
  bool _bookLoading = false;
  String? _bookError;

  // 📏 Резерв під MiniPlayer: оновлюється динамічно за фактичною висотою
  double _miniPlayerReserved = 0.0;

  // ❤️ Стан «Вибране» з можливістю додати/прибрати (toggle)
  bool _favBusy = false;   // йде запит
  bool _isFav = false;     // поточний стан на клієнті

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _inferInitialFavoriteFromModel(); // спроба з моделі (якщо бекенд віддає прапор)
    _maybeLoadFullBook(); // підтягнути відсутню інформацію про книгу
    _syncFavoriteFromServer(); // синхронізація з профілем (GET /favorites)
    fetchChapters(); // паралельно підтягнути розділи
  }

  // Спроба визначити стартовий стан «вибране» з моделі Book (якщо є відповідне поле)
  void _inferInitialFavoriteFromModel() {
    try {
      final dyn = _book as dynamic;
      final v = dyn.isFavorite ?? dyn.is_favorite ?? dyn.favorite ?? dyn.inFavorites ?? dyn.in_favorites;
      final b = _coerceBool(v);
      if (b != null) _isFav = b;
    } catch (_) {
      // якщо в моделі немає таких полів — ігноруємо
    }
  }

  bool? _coerceBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == '1' || s == 'true' || s == 'yes') return true;
      if (s == '0' || s == 'false' || s == 'no') return false;
    }
    return null;
  }

  // Синхронізуємо локальний стан «вибране» з сервером, щоб детальна картка знала поточний статус
  Future<void> _syncFavoriteFromServer() async {
    try {
      final r = await ApiClient.i().get('/favorites');
      if (r.statusCode != 200 || r.data == null) return;

      Iterable items;
      final data = r.data;
      if (data is List) {
        items = data;
      } else if (data is Map<String, dynamic>) {
        items = (data['data'] ?? data['items'] ?? data['favorites'] ?? data['list'] ?? []) as Iterable;
      } else {
        return;
      }

      final ids = <int>{};
      for (final it in items) {
        if (it is int) {
          ids.add(it);
        } else if (it is Map) {
          final raw = (it as Map)['book_id'] ?? (it as Map)['id'] ?? (it as Map)['bookId'];
          if (raw != null) {
            final id = int.tryParse(raw.toString());
            if (id != null) ids.add(id);
          }
        }
      }
      final nowFav = ids.contains(_book.id);
      if (mounted) setState(() => _isFav = nowFav);
    } catch (_) {
      // м’яко ігноруємо помилку — кнопка все одно працює як toggle
    }
  }

  // ✅ Перевірка, чи «урізаний» об’єкт книги. Обов’язково враховуємо поле "series".
  bool _isSparse(Book b) {
    return (b.description == null || b.description!.trim().isEmpty) ||
        b.genres.isEmpty ||
        (b.reader == null || b.reader!.trim().isEmpty) ||
        (b.series == null || b.series!.trim().isEmpty);
  }

  /// 🔎 Нормалізація назви серії з різних форматів відповіді бекенда
  String? _coerceSeries(Map<String, dynamic> raw) {
    final s = raw['series'];
    if (s is String && s.trim().isNotEmpty) return s.trim();
    if (s is Map) {
      final n = (s['name'] ?? s['title']);
      if (n is String && n.trim().isNotEmpty) return n.trim();
    }
    final s1 = raw['series_name'];
    if (s1 is String && s1.trim().isNotEmpty) return s1.trim();
    final s2 = raw['seriesTitle'];
    if (s2 is String && s2.trim().isNotEmpty) return s2.trim();
    return null;
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
          raw = Map<String, dynamic>.from(data);
        } else {
          throw Exception('Несподівана відповідь від сервера');
        }

        // ✅ Примусово приводимо назву серії до ключа "series"
        final normalized = Map<String, dynamic>.from(raw);
        final coercedSeries = _coerceSeries(raw);
        if (coercedSeries != null && coercedSeries.isNotEmpty) {
          normalized['series'] = coercedSeries;
        }

        final full = Book.fromJson(normalized);
        setState(() {
          _book = full;
          _bookLoading = false;
        });

        // Після отримання повної моделі ще раз спробуємо зчитати прапор «вибране»
        _inferInitialFavoriteFromModel();
      } else {
        setState(() {
          _bookLoading = false;
          _bookError = safeHttpStatus('Не вдалося завантажити книгу', resp.statusCode);
        });
      }
    } on DioException catch (e) {
      setState(() {
        _bookLoading = false;
        _bookError = safeErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _bookLoading = false;
        _bookError = safeErrorMessage(e);
      });
    }
  }

  Future<void> fetchChapters({bool refresh = false}) async {
    setState(() {
      isLoading = true;
      error = null;
    });

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
          final ix = loadedChapters.indexWhere((c) => c.id == widget.initialChapter!.id);
          if (ix != -1) startIndex = ix;
        }

        setState(() {
          chapters = loadedChapters;
          selectedChapterIndex = startIndex;
          isLoading = false;
          _playerInitialized = false;
          _initialPositionApplied = false;
        });
      } else {
        setState(() {
          error = safeHttpStatus('Не вдалося завантажити розділи', resp.statusCode);
          isLoading = false;
        });
      }
    } on DioException catch (e) {
      setState(() {
        error = safeErrorMessage(e);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = safeErrorMessage(e);
        isLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      _book = widget.book;
      _playerInitialized = false;
      _initialPositionApplied = false;
      _maybeLoadFullBook(refresh: true);
      _syncFavoriteFromServer();
      fetchChapters();
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  // Привести відносний шлях до абсолютного + форсувати https
  String _absUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final s = path.trim();
    if (s.startsWith('http')) {
      return s.replaceFirst('http://', 'https://');
    }
    return fullResourceUrl(s);
  }

  Future<void> _ensureAudioPrepared({int? startIndex, int? startPosition}) async {
    if (chapters.isEmpty) return;

    final audio = context.read<AudioPlayerProvider>();
    final user = context.read<UserNotifier>().user;
    audio.userType = getUserType(user);

    final targetIndex = startIndex ?? selectedChapterIndex;

    final currentBookId = audio.currentBookId ?? audio.currentBook?.id;
    final sameBook = currentBookId != null && currentBookId == _book.id;

    // Навіть якщо глава/плейлист збігаються, для іншої книги завжди примусово
    // замінюємо плейлист, щоб користувач міг переключитися з явним натисканням Play.
    final forceReplace = !sameBook;

    _logPlayer(
      'ensureAudio: book=${_book.id}, current=$currentBookId, sameBook=$sameBook, forceReplace=$forceReplace, targetIndex=$targetIndex, startPos=${startPosition ?? 'null'}',
    );

    _logPlayer('ensureAudio: setChapters() → userInitiated');
    await audio.setChapters(
      chapters,
      book: _book,
      startIndex: targetIndex,
      bookTitle: _book.title,
      artist: _book.author.trim(),
      coverUrl: _resolveBgUrl(_book),
      userInitiated: true,
      forceReplace: forceReplace,
    );

    if (startPosition != null) {
      _logPlayer('ensureAudio: apply startPosition=$startPosition at index=$targetIndex');
      await audio.seekChapter(
        targetIndex,
        position: Duration(seconds: startPosition),
        persist: false,
      );
      _initialPositionApplied = true;
    }

    if (mounted) {
      setState(() {
        _playerInitialized = true;
        final currentId = audio.currentChapter?.id;
        final idx = currentId != null
            ? chapters.indexWhere((c) => c.id == currentId)
            : targetIndex;
        if (idx >= 0) {
          selectedChapterIndex = idx;
        }
      });
      _logPlayer('ensureAudio: synced UI selectedChapterIndex=$selectedChapterIndex');
    }
  }

  Future<void> _onChapterSelected(Chapter chapter) async {
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index != -1) {
      setState(() => selectedChapterIndex = index);
      _logPlayer('onChapterSelected: chapter=${chapter.id}, index=$index');
      final audio = context.read<AudioPlayerProvider>();
      await _ensureAudioPrepared(startIndex: index);
      await audio.seekChapter(index, position: Duration.zero, persist: false);
      await audio.play();
    }
  }

  Future<void> _onPlayPressed() async {
    final startPos = !_initialPositionApplied ? widget.initialPosition : null;
    _logPlayer('onPlayPressed: startIndex=$selectedChapterIndex, startPos=$startPos');
    await _ensureAudioPrepared(
      startIndex: selectedChapterIndex,
      startPosition: startPos,
    );

    final audio = context.read<AudioPlayerProvider>();
    if (audio.chapters.isNotEmpty) {
      await audio.play();
    }
  }

  String? _resolveBgUrl(Book book) {
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
        coverUrl: bgUrl,
        chapters: chapters,
        selectedChapter: chapters[selectedChapterIndex],
        onChapterSelected: _onChapterSelected,
      ),
    );
  }

  /// ❤️ Перемикач «Вибране» (toggle). Не відключаємо кнопку, щоб тап не «провалювався» в InkWell.
  Future<void> _toggleFavorite() async {
    if (_favBusy) return;

    final userN = context.read<UserNotifier>();
    if (!userN.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Увійдіть, щоб керувати «Вибраним»'),
          action: SnackBarAction(
            label: 'Увійти',
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ),
      );
      return;
    }

    final wantFav = !_isFav;
    setState(() => _favBusy = true);
    try {
      if (wantFav) {
        await ApiClient.i().post('/favorites/${_book.id}');
      } else {
        await ApiClient.i().delete('/favorites/${_book.id}');
      }
      if (!mounted) return;
      setState(() => _isFav = wantFav);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wantFav ? 'Додано у «Вибране»' : 'Прибрано з «Вибраного»')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = context.watch<UserNotifier>().user;
    final userType = getUserType(user);

    // Реклама: guest/free — показываем, paid — нет
    final bool showAds = userType != UserType.paid;

    final media = MediaQuery.of(context);
    final size = media.size;

    // 📐 Адаптивна висота обкладинки з клампом
    double coverHeight = size.height * 0.38;
    coverHeight = coverHeight.clamp(210.0, 510.0);

    final dpr = media.devicePixelRatio;
    int memCacheHeight = (coverHeight * dpr).round();
    if (memCacheHeight > 2200) memCacheHeight = 2200;

    final double topGradientHeight = coverHeight + 120;

    final audio = context.watch<AudioPlayerProvider>();
    final currentChapter = audio.currentChapter;

    final coverUrlAbs = _absUrl(_book.coverUrl);

    // 🔤 Обмежуємо textScaleFactor, щоб верстка не «ламалася» при дуже великих шрифтах
    final clampedScale = media.textScaleFactor.clamp(1.0, 1.35);

    // 📏 Динамічний низ: фактична висота MiniPlayer + SafeArea.
    // РЕЗЕРВ ПІД БАНЕР НЕ ДОДАЄМО — його вже робить GlobalBannerInjector.
    final double reservedBottom =
        (currentChapter != null ? _miniPlayerReserved : 0.0) + media.padding.bottom;

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: MediaQuery(
        data: media.copyWith(textScaleFactor: clampedScale),
        child: isLoading
            ? const LoadingIndicator()
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
            // Фоновий вертикальний градієнт
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

            // Контент з pull-to-refresh та ДИНАМІЧНИМ нижнім відступом
            RefreshIndicator(
              onRefresh: () async {
                await _maybeLoadFullBook(refresh: true);
                await _syncFavoriteFromServer();
                await fetchChapters(refresh: true);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + reservedBottom),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                    const BoxConstraints(maxWidth: 720), // 📱 читабельна ширина на планшетах
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (coverUrlAbs.isNotEmpty)
                          Center(
                            child: Container(
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
                                child: CachedNetworkImage(
                                  imageUrl: coverUrlAbs,
                                  cacheManager: BookaImageCacheManager.instance,
                                  height: coverHeight,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => SizedBox(
                                    height: coverHeight,
                                    child: const LoadingIndicator(size: 80),
                                  ),
                                  errorWidget: (_, __, ___) => SizedBox(
                                    height: coverHeight,
                                    child: const Icon(Icons.broken_image, size: 48),
                                  ),
                                  memCacheHeight: memCacheHeight,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          _book.title.isNotEmpty ? _book.title : 'Без назви',
                          textAlign: TextAlign.start,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
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

                        // ✅ Картка метаданих + ❤️ праворуч (toggle)
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
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Ліва частина — текстові метадані
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_book.series != null &&
                                            _book.series!.trim().isNotEmpty)
                                          Text('Серія: ${_book.series}',
                                              style: theme.textTheme.bodySmall),
                                        if (_book.genres.isNotEmpty)
                                          Text(
                                            'Жанри: ${_book.genres.join(', ')}',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        if (_book.duration.isNotEmpty)
                                          Text(
                                            'Тривалість: ${formatBookDuration(_book.duration, locale: "uk")}',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        if (_bookLoading) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              LoadingIndicator(size: 16),
                                              SizedBox(width: 8),
                                              Text('Оновлення даних книги'),
                                            ],
                                          ),
                                        ],
                                        if (_bookError != null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _bookError!,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  // Права частина — велика кнопка «серце» (toggle)
                                  SizedBox(
                                    height: 36,
                                    width: 36,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: _isFav
                                          ? 'Прибрати з «Вибраного»'
                                          : 'Додати у «Вибране»',
                                      onPressed: () {
                                        if (_favBusy) return; // не вимикаємо кнопку, щоб не «провалюватися»
                                        _toggleFavorite();
                                      },
                                      icon: _favBusy
                                          ? const LoadingIndicator(size: 24)
                                          : Icon(
                                        _isFav ? Icons.favorite : Icons.favorite_border,
                                        size: 26,
                                      ),
                                      color: _isFav ? Colors.redAccent : cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        if ((_book.description ?? '').trim().isNotEmpty)
                          Text(
                            _book.description!.trim(),
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                          ),

                        const SizedBox(height: 16),

                        // 🔗 Клікабельний рядок для гостя: веде на екран логіну
                        if (userType == UserType.guest)
                          InkWell(
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                    builder: (_) => const LoginScreen()),
                              );
                            },
                            child: Text(
                              'Увійдіть, щоб отримати повний доступ до всіх розділів.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.primary,
                                decoration: TextDecoration.underline,
                                decorationThickness: 1.5,
                              ),
                            ),
                          ),

                        if (chapters.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _onPlayPressed,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                _playerInitialized
                                    ? 'Продовжити відтворення'
                                    : 'Слухати книгу',
                              ),
                            ),
                          ),
                        ],

                        if (userType == UserType.free)
                          Text(
                            'Безкоштовний тариф відтворює з рекламою. Оформіть підписку, щоб слухати без реклами.',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // MiniPlayer поверх усього
            if (currentChapter != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SizeReporter(
                  onSize: (sz) {
                    final newH = (sz.height).clamp(0.0, 320.0);
                    if ((newH - _miniPlayerReserved).abs() > 0.5) {
                      setState(() => _miniPlayerReserved = newH);
                    }
                  },
                  child: MiniPlayerWidget(
                    chapter: currentChapter,
                    bookTitle: _book.title,
                    coverUrl: _resolveBgUrl(_book),
                    onExpand: _openFullPlayer,
                    // 👇 если показываем рекламу — прижимаем к баннеру
                    bottomSafeMargin: showAds ? 0 : 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SizeReporter extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onSize;

  const _SizeReporter({required this.child, required this.onSize});

  @override
  State<_SizeReporter> createState() => _SizeReporterState();
}

class _SizeReporterState extends State<_SizeReporter> {
  Size _last = Size.zero;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !mounted) return;
      final sz = box.size;
      if (sz != _last) {
        _last = sz;
        widget.onSize(sz);
      }
    });
    return widget.child;
  }
}
