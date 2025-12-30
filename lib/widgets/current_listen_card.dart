// lib/widgets/current_listen_card.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/constants.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/widgets/loading_indicator.dart';
import '../core/network/image_cache.dart';

// Імпорт для переходу на сторінку книги
import 'package:booka_app/screens/book_detail_screen.dart';

class CurrentListenCard extends StatefulWidget {
  const CurrentListenCard({
    Key? key,
    this.onContinue,
    this.margin,
    this.height,
    this.widthFactor = 0.90,
    this.autoHydrate = true,
  }) : super(key: key);

  final VoidCallback? onContinue;
  final EdgeInsetsGeometry? margin;
  final double? height;
  final double widthFactor;
  final bool autoHydrate;

  static const double _kRadius = 14.0;
  static const Color _kBlue100 = Color(0xFFBBDEFB);
  static const Color _kPlayYellow = Color(0xFFFFF59D);
  static const double _kTileHeight = 112.0;

  static const String _kCurrentListenKey = 'current_listen';

  @override
  State<CurrentListenCard> createState() => _CurrentListenCardState();
}

class _CurrentListenCardState extends State<CurrentListenCard> {
  bool _hydrating = false;
  String? _remoteCoverUrl;
  int? _coverForBookId;
  bool _loadingCover = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoHydrate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateLocalFirst());
    }
  }

  Future<void> _hydrateLocalFirst() async {
    if (!mounted || _hydrating) return;
    setState(() => _hydrating = true);
    try {
      final audio = context.read<AudioPlayerProvider>();
      final hasLocal = await audio.hasSavedSession();
      if (!hasLocal) {
        await audio.hydrateFromServerIfAvailable();
      }
    } finally {
      if (mounted) setState(() => _hydrating = false);
    }
  }

  Future<void> _ensureCoverLoaded(int bookId) async {
    if (_loadingCover) return;
    if (_coverForBookId == bookId && _remoteCoverUrl != null) return;

    _loadingCover = true;
    try {
      final r = await ApiClient.i().get(
        '/abooks/$bookId',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (r.statusCode == 200) {
        final data = (r.data is Map)
            ? Map<String, dynamic>.from(r.data as Map)
            : <String, dynamic>{};
        final url = _resolveThumbOrCoverUrl(data);
        if (mounted) {
          setState(() {
            _coverForBookId = bookId;
            _remoteCoverUrl = url;
          });
        }
      }
    } catch (_) {
    } finally {
      _loadingCover = false;
    }
  }

  static Future<int?> _loadSavedPosition({int? expectBookId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(CurrentListenCard._kCurrentListenKey);
      if (raw == null || raw.isEmpty) return null;

      final Map<String, dynamic> data = json.decode(raw);
      final Map<String, dynamic>? book =
      (data['book'] as Map?)?.cast<String, dynamic>();
      final pos = data['position'];

      if (expectBookId != null && book != null) {
        final savedId = book['id'];
        final savedBookId =
        (savedId is int) ? savedId : int.tryParse('$savedId');
        if (savedBookId != expectBookId) return null;
      }

      return (pos is int) ? pos : int.tryParse('$pos');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, p, _) {
        final book = p.currentBook;
        final chapter = p.currentChapter;
        if (book == null || chapter == null) return const SizedBox.shrink();

        if (_coverForBookId != book.id) {
          _remoteCoverUrl = null;
          _coverForBookId = null;
        }

        final theme = Theme.of(context);

        String? coverUrl = _resolveThumbOrCoverUrl(book.toJson());

        if (coverUrl == null || coverUrl.isEmpty) {
          final chBookMap = (chapter.book is Map)
              ? Map<String, dynamic>.from(chapter.book!)
              : const <String, dynamic>{};
          coverUrl = _resolveThumbOrCoverUrl(chBookMap);
        }

        if ((coverUrl == null || coverUrl.isEmpty) && _remoteCoverUrl == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ensureCoverLoaded(book.id);
          });
        }
        coverUrl ??= _remoteCoverUrl;

        final bool isDark = theme.brightness == Brightness.dark;
        final Color cardBg = isDark
            ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.4)
            : CurrentListenCard._kBlue100;

        final double tileHeight =
            widget.height ?? CurrentListenCard._kTileHeight;
        final double coverWidth = tileHeight * 3 / 4;

        final bool needFallback = !p.isPlaying && p.position.inSeconds == 0;

        return FutureBuilder<int?>(
          future: needFallback
              ? _loadSavedPosition(expectBookId: book.id)
              : Future.value(null),
          builder: (context, snap) {
            final int rawPos = (p.position.inSeconds > 0)
                ? p.position.inSeconds
                : (snap.data ?? 0);

            final int durationSec = (p.duration.inSeconds > 0)
                ? p.duration.inSeconds
                : (chapter.duration ?? 0);

            final int positionSec =
            (durationSec > 0) ? rawPos.clamp(0, durationSec) : rawPos;

            final double? progressValue = (durationSec > 0)
                ? (positionSec / durationSec).clamp(0.0, 1.0)
                : null;

            final bool isThisBookPlaying = p.isPlaying;

            return FractionallySizedBox(
              widthFactor: widget.widthFactor,
              alignment: Alignment.center,
              child: Container(
                margin:
                widget.margin ?? const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius:
                  BorderRadius.circular(CurrentListenCard._kRadius),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                      color: theme.colorScheme.primary
                          .withOpacity(isDark ? 0.10 : 0.06),
                    ),
                  ],
                ),
                child: Material(
                  color: cardBg,
                  borderRadius:
                  BorderRadius.circular(CurrentListenCard._kRadius),
                  child: SizedBox(
                    height: tileHeight,
                    child: Stack(
                      children: [
                        InkWell(
                          borderRadius:
                          BorderRadius.circular(CurrentListenCard._kRadius),
                          onTap: null,
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft:
                                  Radius.circular(CurrentListenCard._kRadius),
                                  bottomLeft:
                                  Radius.circular(CurrentListenCard._kRadius),
                                ),
                                child: _CoverCompact(
                                  coverUrl: coverUrl,
                                  height: tileHeight,
                                  width: coverWidth,
                                  playing: isThisBookPlaying,
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                  const EdgeInsets.fromLTRB(10, 8, 10, 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(right: 36),
                                        child: Text(
                                          book.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Padding(
                                        padding: const EdgeInsets.only(right: 36),
                                        child: Text(
                                          'Розділ ${chapter.order ?? chapter.id} · '
                                              '${_fmt(Duration(seconds: positionSec))} / '
                                              '${durationSec > 0 ? _fmt(Duration(seconds: durationSec)) : '—:—'}'
                                              '${_hydrating ? '  ·  оновлення…' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.7),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: SizedBox(
                                          height: 3,
                                          child: LinearProgressIndicator(
                                            value: progressValue,
                                            backgroundColor: theme
                                                .colorScheme.surfaceVariant
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              minHeight: 28),
                                          child: ElevatedButton(
                                            onPressed: () {
                                              p.handleBottomPlayTap();
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                              CurrentListenCard._kPlayYellow,
                                              foregroundColor: Colors.black87,
                                              elevation: 0,
                                              padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 4,
                                              ),
                                              tapTargetSize: MaterialTapTargetSize
                                                  .shrinkWrap,
                                              minimumSize: const Size(0, 28),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius.circular(10),
                                              ),
                                              visualDensity: const VisualDensity(
                                                horizontal: -2,
                                                vertical: -3,
                                              ),
                                            ),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 180),
                                              switchInCurve: Curves.easeOut,
                                              switchOutCurve: Curves.easeIn,
                                              layoutBuilder: (currentChild,
                                                  previousChildren) =>
                                                  Stack(
                                                    alignment: Alignment.center,
                                                    children: <Widget>[
                                                      ...previousChildren,
                                                      if (currentChild != null)
                                                        currentChild,
                                                    ],
                                                  ),
                                              child: isThisBookPlaying
                                                  ? const SizedBox(
                                                key: ValueKey('eq'),
                                                height: 18,
                                                child: _EqualizerIndicator(
                                                  bars: 5,
                                                  barWidth: 3,
                                                  maxHeight: 18,
                                                  gap: 3,
                                                ),
                                              )
                                                  : Row(
                                                key: const ValueKey('text'),
                                                mainAxisSize:
                                                MainAxisSize.min,
                                                children: const [
                                                  Icon(
                                                    Icons.play_arrow_rounded,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Продовжити',
                                                    style: TextStyle(
                                                        fontWeight:
                                                        FontWeight.w700),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _PulseArrowButton(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      BookDetailScreen(book: book),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Універсальний метод для отримання обкладинки.
  /// 🔥 ВИПРАВЛЕНО: Тепер використовує глобальну функцію ensureAbsoluteImageUrl.
  static String? _resolveThumbOrCoverUrl(Map<String, dynamic> book) {
    final rawValue = (
        book['thumb_url'] ??
            book['thumbUrl'] ??
            book['cover_url'] ??
            book['coverUrl'] ??
            book['cover']
    )?.toString();

    return ensureAbsoluteImageUrl(rawValue);
  }

  static String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '${hh.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
  }
}

class _PulseArrowButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PulseArrowButton({required this.onTap});

  @override
  State<_PulseArrowButton> createState() => _PulseArrowButtonState();
}

class _PulseArrowButtonState extends State<_PulseArrowButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? Colors.black.withOpacity(0.3)
        : Colors.white.withOpacity(0.6);

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: widget.onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 24,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverCompact extends StatelessWidget {
  const _CoverCompact({
    required this.coverUrl,
    required this.height,
    required this.width,
    required this.playing,
  });

  final String? coverUrl;
  final double height;
  final double width;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    Widget _basePlaceholder() => Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      alignment: Alignment.center,
      child: const Icon(Icons.audiotrack_rounded),
    );

    Widget _loadingPlaceholder() => Stack(
      children: [
        _basePlaceholder(),
        const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: LoadingIndicator(size: 22),
          ),
        ),
      ],
    );

    final image = (coverUrl != null && coverUrl!.isNotEmpty)
        ? CachedNetworkImage(
      imageUrl: coverUrl!,
      cacheManager: BookaImageCacheManager.instance,
      width: width,
      height: height,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => _loadingPlaceholder(),
      errorWidget: (_, __, ___) => _basePlaceholder(),
    )
        : _basePlaceholder();

    return Stack(
      children: [
        image,
        Positioned(
          right: 6,
          bottom: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              playing ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _EqualizerIndicator extends StatefulWidget {
  const _EqualizerIndicator({
    Key? key,
    this.bars = 5,
    this.barWidth = 3,
    this.maxHeight = 16,
    this.gap = 3,
    this.period = const Duration(milliseconds: 900),
    this.color,
  }) : super(key: key);

  final int bars;
  final double barWidth;
  final double maxHeight;
  final double gap;
  final Duration period;
  final Color? color;

  @override
  State<_EqualizerIndicator> createState() => _EqualizerIndicatorState();
}

class _EqualizerIndicatorState extends State<_EqualizerIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        DefaultTextStyle.of(context).style.color ??
        Colors.black87;

    return Semantics(
      label: 'Відтворюється',
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.bars, (i) {
              final phase = (i / widget.bars) * 2 * math.pi;
              final amp = 0.35 +
                  0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * t + phase));
              final h = amp * widget.maxHeight;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.gap / 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: widget.barWidth,
                  height: h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(widget.barWidth),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}