// lib/screens/book_detail_screen.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:booka_app/screens/login_screen.dart';
import 'package:booka_app/screens/subscriptions_screen.dart';

import 'package:booka_app/core/utils/duration_format.dart';
import 'package:booka_app/core/security/safe_errors.dart';
import 'package:booka_app/core/network/favorites_api.dart';
import 'package:booka_app/repositories/profile_repository.dart';

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
  late Book _book;

  List<Chapter> chapters = [];
  int selectedChapterIndex = 0;
  bool _userSelectedChapter = false;

  bool isLoading = true;
  String? error;

  bool _playerInitialized = false;
  bool _autoStartPending = false;

  bool _bookLoading = false;
  String? _bookError;

  double _miniPlayerReserved = 0.0;

  bool _favBusy = false;
  bool _isFav = false;

  StreamSubscription? _updateSub;
  AudioPlayerProvider? _audioProvider;

  void _onAudioChanged() {
    final audio = _audioProvider;
    if (audio == null || chapters.isEmpty) return;
    _syncSelectedChapterFromPlayer(audio);
  }

  @override
  void initState() {
    super.initState();
    _book = widget.book;

    _inferInitialFavoriteFromModel();
    _checkStatusFromCache();

    _updateSub = ProfileRepository.I.onUpdate.listen((_) {
      if (mounted) _checkStatusFromCache();
    });

    _maybeLoadFullBook();
    _syncFavoriteFromServer();
    fetchChapters();
  }

  @override
  void dispose() {
    _audioProvider?.removeListener(_onAudioChanged);
    _updateSub?.cancel();
    super.dispose();
  }

  void _checkStatusFromCache() {
    final map = ProfileRepository.I.getCachedMap();
    if (map == null) return;

    final rawFavs = map['favorites'];
    bool found = false;

    if (rawFavs is List) {
      for (final item in rawFavs) {
        int? id;
        if (item is int) {
          id = item;
        } else if (item is Map) {
          final rawId = item['id'] ?? item['book_id'] ?? item['bookId'];
          if (rawId != null) {
            id = int.tryParse(rawId.toString());
          }
        }
        if (id == _book.id) {
          found = true;
          break;
        }
      }
    }

    if (found != _isFav) {
      setState(() => _isFav = found);
    }
  }

  void _inferInitialFavoriteFromModel() {
    try {
      final dyn = _book as dynamic;
      final v = dyn.isFavorite ?? dyn.is_favorite ?? dyn.favorite ?? dyn.inFavorites ?? dyn.in_favorites;
      final b = _coerceBool(v);
      if (b != null) _isFav = b;
    } catch (_) {
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
      if (mounted && nowFav != _isFav) setState(() => _isFav = nowFav);
    } catch (_) {
    }
  }

  bool _isSparse(Book b) {
    return (b.description == null || b.description!.trim().isEmpty) ||
        b.genres.isEmpty ||
        (b.reader == null || b.reader!.trim().isEmpty) ||
        (b.series == null || b.series!.trim().isEmpty);
  }

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

    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);

    try {
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
        } else if (audioProvider.currentBook?.id == _book.id &&
            audioProvider.currentChapter != null) {
          final playingIdx = loadedChapters.indexWhere(
                (c) => c.id == audioProvider.currentChapter!.id,
          );
          if (playingIdx != -1) startIndex = playingIdx;
        }

        setState(() {
          chapters = loadedChapters;
          selectedChapterIndex = startIndex;
          _userSelectedChapter = false;
          isLoading = false;
          _playerInitialized = false;
          _autoStartPending = true;
        });

        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_playerInitialized && _autoStartPending) {
              _initAudioPlayer();
            }
          });
        }
      } else {
        setState(() {
          error = safeHttpStatus('Не вдалося завантажити розділи', resp.statusCode);
          isLoading = false;
        });
        await audioProvider.pause();
      }
    } on DioException catch (e) {
      setState(() {
        error = safeErrorMessage(e);
        isLoading = false;
      });
      await audioProvider.pause();
    } catch (e) {
      setState(() {
        error = safeErrorMessage(e);
        isLoading = false;
      });
      await audioProvider.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newAudio = context.read<AudioPlayerProvider>();
    if (!identical(_audioProvider, newAudio)) {
      _audioProvider?.removeListener(_onAudioChanged);
      _audioProvider = newAudio;
      _audioProvider?.addListener(_onAudioChanged);
      _onAudioChanged();
    }
  }

  @override
  void didUpdateWidget(covariant BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      _book = widget.book;
      _playerInitialized = false;
      _autoStartPending = true;
      _checkStatusFromCache();
      _maybeLoadFullBook(refresh: true);
      fetchChapters();
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  String _absUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final s = path.trim();
    if (s.startsWith('http')) {
      return s.replaceFirst('http://', 'https://');
    }
    return fullResourceUrl(s);
  }

  void _initAudioPlayer() {
    if (_playerInitialized || chapters.isNotEmpty == false) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final audio = context.read<AudioPlayerProvider>();
      final user = context.read<UserNotifier>().user;
      audio.userType = getUserType(user);

      int startIndex = selectedChapterIndex;
      final current = audio.currentChapter;
      final currentBookId = audio.currentBook?.id;
      final sameBook = current != null && currentBookId == _book.id;

      if (sameBook) {
        final idx = chapters.indexWhere((c) => c.id == current!.id);
        if (idx != -1 && idx != selectedChapterIndex) {
          setState(() => selectedChapterIndex = idx);
        }
        setState(() {
          _playerInitialized = true;
          _autoStartPending = false;
        });
        return;
      }

      if (audio.currentBook != null) {
        final savedIdx = await audio.getSavedChapterIndex(_book.id, chapters);
        if (savedIdx != null && savedIdx != selectedChapterIndex) {
          setState(() => selectedChapterIndex = savedIdx);
        }
        setState(() {
          _playerInitialized = true;
          _autoStartPending = false;
        });
        return;
      }

      final ignoreSavedPosition = widget.initialChapter != null;

      // 🔥 FIX: Передаем context в setChapters
      await audio.setChapters(
        chapters,
        book: _book,
        startIndex: startIndex,
        bookTitle: _book.title,
        artist: _book.author.trim(),
        coverUrl: _resolveBgUrl(_book),
        ignoreSavedPosition: ignoreSavedPosition,
        context: context,
      );

      _syncSelectedChapterFromPlayer(audio);

      if (widget.initialPosition != null) {
        await audio.seekChapter(startIndex, position: Duration(seconds: widget.initialPosition!), persist: false);
      } else if (widget.initialChapter != null) {
        await audio.seekChapter(startIndex, position: Duration.zero, persist: false);
      }

      if (mounted) {
        setState(() {
          _playerInitialized = true;
          _autoStartPending = false;
        });
      }
    });
  }

  void _syncSelectedChapterFromPlayer(AudioPlayerProvider audio) {
    final current = audio.currentChapter;
    if (current == null) return;

    final idx = chapters.indexWhere((c) => c.id == current.id);
    if (idx != -1 && idx != selectedChapterIndex) {
      setState(() => selectedChapterIndex = idx);
    }
  }

  Future<void> _onChapterSelected(Chapter chapter) async {
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index == -1) return;

    setState(() {
      selectedChapterIndex = index;
      _userSelectedChapter = true;
    });

    final audio = context.read<AudioPlayerProvider>();

    bool needReload = (audio.currentBook?.id != _book.id) ||
        (audio.chapters.length != chapters.length);

    if (needReload) {
      // 🔥 FIX: Передаем context
      await audio.setChapters(
        chapters,
        book: _book,
        startIndex: index,
        bookTitle: _book.title,
        artist: _book.author.trim(),
        coverUrl: _resolveBgUrl(_book),
        ignoreSavedPosition: true,
        context: context,
      );

      // 🔥 FIX: Передаем context
      await audio.play(context);
    } else {
      await audio.seekChapter(index, position: Duration.zero, persist: false);
      // 🔥 FIX: Передаем context
      await audio.play(context);
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
        await FavoritesApi.add(_book.id);
      } else {
        await FavoritesApi.remove(_book.id);
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

  Future<void> _onPlayButtonTap() async {
    if (isLoading || chapters.isEmpty) return;

    final audio = context.read<AudioPlayerProvider>();
    final user = context.read<UserNotifier>().user;
    final userType = getUserType(user);

    if (audio.currentBook?.id == _book.id) {
      final bool needsPlaylistUpdate = (userType != UserType.guest) &&
          (audio.chapters.length < chapters.length);

      final currentCover = audio.currentBook?.coverUrl;
      final screenCover = _book.coverUrl;
      final bool metadataMissing = (currentCover == null || currentCover.isEmpty) &&
          (screenCover != null && screenCover.isNotEmpty);

      if (needsPlaylistUpdate || metadataMissing) {
        final currentPos = audio.player.position;
        int resumeIndex = 0;
        if (audio.currentChapter != null) {
          resumeIndex = chapters.indexWhere((c) => c.id == audio.currentChapter!.id);
          if (resumeIndex == -1) resumeIndex = 0;
        }

        // 🔥 FIX: Передаем context
        await audio.setChapters(
          chapters,
          book: _book,
          startIndex: resumeIndex,
          bookTitle: _book.title,
          artist: _book.author.trim(),
          coverUrl: _resolveBgUrl(_book),
          initialPositionOverride: currentPos,
          context: context,
        );

        if (!audio.isPlaying) {
          // 🔥 FIX: Передаем context
          await audio.play(context);
        }
      } else {
        if (!audio.isPlaying) {
          // 🔥 FIX: Передаем context
          await audio.play(context);
        }
      }
    } else {
      int startIndex = selectedChapterIndex;
      if (!_userSelectedChapter) {
        final savedIdx = await audio.getSavedChapterIndex(_book.id, chapters);
        if (savedIdx != null) {
          startIndex = savedIdx;
          if (startIndex != selectedChapterIndex) {
            setState(() => selectedChapterIndex = startIndex);
          }
        }
      }

      // 🔥 FIX: Передаем context
      await audio.setChapters(
        chapters,
        book: _book,
        startIndex: startIndex,
        bookTitle: _book.title,
        artist: _book.author.trim(),
        coverUrl: _resolveBgUrl(_book),
        context: context,
      );
      // 🔥 FIX: Передаем context
      await audio.play(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = context.watch<UserNotifier>().user;
    final userType = getUserType(user);

    final bool showAds = userType != UserType.paid;

    final media = MediaQuery.of(context);
    final size = media.size;

    double coverHeight = size.height * 0.38;
    coverHeight = coverHeight.clamp(210.0, 510.0);

    final dpr = media.devicePixelRatio;
    int memCacheHeight = (coverHeight * dpr).round();
    if (memCacheHeight > 2200) memCacheHeight = 2200;

    final double topGradientHeight = coverHeight + 120;

    final audio = context.watch<AudioPlayerProvider>();
    final currentChapter = audio.currentChapter;

    final coverUrlAbs = _absUrl(_book.coverUrl);

    final clampedScale = media.textScaleFactor.clamp(1.0, 1.35);

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
                _checkStatusFromCache();
                await _syncFavoriteFromServer();
                await fetchChapters(refresh: true);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + reservedBottom),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                    const BoxConstraints(maxWidth: 720),
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

                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: (isLoading || error != null)
                                      ? null
                                      : _onPlayButtonTap,
                                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                                  label: Text(
                                    isLoading ? 'Завантаження...' : 'Слухати',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    foregroundColor: cs.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: Material(
                                color: cs.surfaceContainerHighest.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _toggleFavorite,
                                  child: Center(
                                    child: _favBusy
                                        ? const LoadingIndicator(size: 20)
                                        : Icon(
                                      _isFav ? Icons.favorite : Icons.favorite_border,
                                      color: _isFav ? Colors.redAccent : cs.primary,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

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
                          ),
                        ),

                        const SizedBox(height: 24),

                        if ((_book.description ?? '').trim().isNotEmpty) ...[
                          Text(
                            'Про книгу',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _book.description!.trim(),
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (userType == UserType.guest) ...[
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
                          const SizedBox(height: 16),
                        ],

                        if (userType == UserType.free) ...[
                          Text.rich(
                            TextSpan(
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary),
                              children: [
                                const TextSpan(
                                  text: 'Безкоштовний тариф відтворює з рекламою. Оформіть ',
                                ),
                                TextSpan(
                                  text: 'підписку',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const SubscriptionsScreen(),
                                        ),
                                      );
                                    },
                                ),
                                const TextSpan(
                                  text: ', щоб слухати без реклами.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

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
                    // ✅ ПОКАЗУЄМО ДАНІ ТОГО, ЩО ГРАЄ В ФОНІ
                    bookTitle: (audio.currentBook?.id == _book.id)
                        ? _book.title
                        : (audio.currentBook?.title ?? _book.title),
                    coverUrl: (audio.currentBook?.id == _book.id)
                        ? _resolveBgUrl(_book)
                        : (audio.currentBook != null
                        ? _resolveBgUrl(audio.currentBook!)
                        : _resolveBgUrl(_book)),
                    onExpand: _openFullPlayer,
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