// ПУТЬ: lib/widgets/mini_player.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/screens/login_screen.dart'; // Переконайтесь, що імпорт правильний
import '../core/network/image_cache.dart';

enum MiniTimeLayout { sides, above }

class MiniPlayerWidget extends StatefulWidget {
  final Chapter chapter;
  final String bookTitle;
  final String? coverUrl;
  final VoidCallback onExpand;
  final MiniTimeLayout timeLayout;
  final double bottomSafeMargin;

  const MiniPlayerWidget({
    super.key,
    required this.chapter,
    required this.bookTitle,
    required this.onExpand,
    this.coverUrl,
    this.timeLayout = MiniTimeLayout.sides,
    this.bottomSafeMargin = 8,
  });

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget> {
  bool _showedEndDialog = false;

  // 🔥 ЛОКАЛЬНИЙ СТАН ДЛЯ СЛАЙДЕРА (Щоб не смикався і не залежав від провайдера)
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
    audio.onGuestFirstChapterEnd = () {
      final isGuest = Provider.of<UserNotifier>(context, listen: false).isGuest;
      if (!isGuest || _showedEndDialog) return;

      _showedEndDialog = true;
      Future.microtask(() {
        showDialog(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Доступ обмежено'),
            content: const Text(
              'Авторизуйтеся, щоб отримати доступ до інших розділів.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Скасувати'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    WidgetsBinding.instance.focusManager.primaryFocus?.unfocus();
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 220),
                        reverseTransitionDuration: const Duration(milliseconds: 180),
                        pageBuilder: (_, __, ___) => const LoginScreen(),
                        transitionsBuilder: (_, anim, __, child) {
                          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
                          return FadeTransition(opacity: curved, child: child);
                        },
                      ),
                    );
                  });
                },
                child: const Text('Увійти'),
              ),
            ],
          ),
        );
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final audio = context.watch<AudioPlayerProvider>();
    final currentChapter = audio.currentChapter;
    final connectivityMessage = audio.connectivityMessage;

    if (audio.currentUrl == null || currentChapter == null) {
      return const SizedBox.shrink();
    }

    // 🔥 ВИЗНАЧЕННЯ ПОЗИЦІЇ:
    // Якщо тягнемо (_isDragging) — беремо локальне значення (_dragValue).
    // Якщо ні — беремо реальну позицію з провайдера.
    final pos = _isDragging
        ? Duration(seconds: _dragValue.floor())
        : audio.position;

    final rawDur = audio.duration;
    final metaDur = (currentChapter.duration ?? 0) > 0
        ? Duration(seconds: currentChapter.duration!)
        : Duration.zero;
    final knownDur = rawDur > Duration.zero ? rawDur : metaDur;
    final dur = pos > knownDur ? pos : knownDur;
    final hasDur = dur.inSeconds > 0;

    final provisionalMax = (pos.inSeconds + 1).clamp(1, 24 * 60 * 60).toDouble();
    final sliderMax = hasDur ? dur.inSeconds.toDouble() : provisionalMax;
    final sliderValue = pos.inSeconds.toDouble().clamp(0.0, sliderMax);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      minimum: EdgeInsets.only(bottom: widget.bottomSafeMargin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.92),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connectivityMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.error.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: cs.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                connectivityMessage,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Row(
                      children: [
                        _CoverThumb(url: widget.coverUrl),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentChapter.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.bookTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        Semantics(
                          label: audio.isPlaying ? 'Пауза' : 'Відтворити',
                          button: true,
                          child: _RoundPlayButton(
                            size: 38,
                            isPlaying: audio.isPlaying,
                            onTap: audio.togglePlayback,
                          ),
                        ),

                        const SizedBox(width: 6),

                        Semantics(
                          label: 'Розгорнути плеєр',
                          button: true,
                          child: IconButton(
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _handleExpandTap,
                            icon: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.expand_less_rounded),
                                if (context.read<UserNotifier>().isGuest)
                                  Positioned(
                                    right: -6,
                                    top: -6,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: cs.errorContainer,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: cs.onErrorContainer, width: 1),
                                      ),
                                      child: Icon(Icons.lock_rounded, size: 12, color: cs.onErrorContainer),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ===== СЛАЙДЕР + ЧАС (ВИПРАВЛЕНО) =====
                    Builder(
                      builder: (_) {
                        final slider = SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: SliderComponentShape.noOverlay,
                            minThumbSeparation: 0,
                          ),
                          child: Slider(
                            value: sliderValue,
                            min: 0.0,
                            max: sliderMax,
                            // 🔥 1. Початок драгу: вмикаємо локальний режим
                            onChangeStart: (val) {
                              setState(() {
                                _isDragging = true;
                                _dragValue = val;
                              });
                            },
                            // 🔥 2. Процес: оновлюємо локальну змінну (плавно)
                            onChanged: (val) {
                              setState(() {
                                _dragValue = val;
                              });
                            },
                            // 🔥 3. Кінець: відправляємо seek() і тільки потім вимикаємо локальний режим
                            onChangeEnd: (val) async {
                              setState(() => _dragValue = val); // На всякий випадок
                              await context.read<AudioPlayerProvider>().seek(Duration(seconds: val.floor()));

                              if (mounted) {
                                setState(() {
                                  _isDragging = false;
                                });
                              }
                            },
                          ),
                        );

                        final timeStyle =
                        theme.textTheme.labelSmall?.copyWith(color: cs.onSurface.withOpacity(0.6));

                        if (widget.timeLayout == MiniTimeLayout.sides) {
                          return Row(
                            children: [
                              Text(_fmt(pos), style: timeStyle),
                              const SizedBox(width: 8),
                              Expanded(child: slider),
                              const SizedBox(width: 8),
                              Text(hasDur ? _fmt(dur) : '--:--', style: timeStyle),
                            ],
                          );
                        } else {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(_fmt(pos), style: timeStyle),
                                  const Spacer(),
                                  Text(hasDur ? _fmt(dur) : '--:--', style: timeStyle),
                                ],
                              ),
                              const SizedBox(height: 6),
                              slider,
                            ],
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 6),

                    // Кнопки -15/+15, Next/Prev
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          tooltip: 'Попередній розділ',
                          onPressed: _previousChapter,
                          icon: const Icon(Icons.skip_previous_rounded, size: 22),
                        ),
                        IconButton(
                          tooltip: '-15 с',
                          onPressed: () => _skipSeconds(-15, effectiveDuration: dur),
                          icon: const Icon(Icons.replay_10_rounded, size: 22),
                        ),
                        IconButton(
                          tooltip: '+15 с',
                          onPressed: () => _skipSeconds(15, effectiveDuration: dur),
                          icon: const Icon(Icons.forward_10_rounded, size: 22),
                        ),
                        IconButton(
                          tooltip: 'Наступний розділ',
                          onPressed: _nextChapter,
                          icon: const Icon(Icons.skip_next_rounded, size: 22),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final hh = d.inHours;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hh > 0) {
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }

  void _handleExpandTap() {
    final user = context.read<UserNotifier>();
    if (user.isGuest) {
      final theme = Theme.of(context);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          final media = MediaQuery.of(ctx);
          final clamped = media.textScaleFactor.clamp(1.0, 1.3);
          return MediaQuery(
            data: media.copyWith(textScaleFactor: clamped),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 12,
                    bottom: 20 + media.padding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Доступ обмежено',
                        style: Theme.of(ctx).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'У гостьовому режимі доступна лише перша глава. '
                            'Увійдіть, щоб отримати повний доступ до усіх розділів і керування прогресом.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).maybePop();
                            Future.microtask(() {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(builder: (_) => const LoginScreen()),
                              );
                            });
                          },
                          child: const Text('Увійти / Зареєструватися'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          child: const Text('Закрити'),
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
      return;
    }

    widget.onExpand();
  }

  Future<void> _skipSeconds(int delta, {required Duration effectiveDuration}) async {
    final audio = context.read<AudioPlayerProvider>();
    // Тут теж: якщо тягнемо — беремо від пальця, інакше — від реальної позиції
    final basePos = _isDragging
        ? Duration(seconds: _dragValue.toInt())
        : audio.position;

    var newPos = basePos + Duration(seconds: delta);

    if (newPos < Duration.zero) newPos = Duration.zero;
    if (effectiveDuration > Duration.zero && newPos > effectiveDuration) {
      newPos = effectiveDuration - const Duration(milliseconds: 500);
    }
    await audio.seek(newPos);
  }

  Future<void> _nextChapter() => context.read<AudioPlayerProvider>().nextChapter();
  Future<void> _previousChapter() => context.read<AudioPlayerProvider>().previousChapter();
}

class _CoverThumb extends StatelessWidget {
  final String? url;
  const _CoverThumb({this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const size = 44.0;

    if (url == null || url!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(Icons.headphones_rounded, color: cs.onSurfaceVariant),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: url!,
          cacheManager: BookaImageCacheManager.instance,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 160),
          errorWidget: (_, __, ___) => Container(
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _RoundPlayButton extends StatelessWidget {
  final double size;
  final bool isPlaying;
  final VoidCallback onTap;

  const _RoundPlayButton({
    required this.size,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = isPlaying ? Icons.pause : Icons.play_arrow;
    final iconSize = size * 0.58;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFFF48FB1),
                    Color(0xFF7C4DFF),
                    Color(0xFF64B5F6),
                    Color(0xFF26A69A),
                    Color(0xFFF48FB1),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    offset: const Offset(0, 2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: size - 8,
                  height: size - 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize, color: Color(0xFF7C4DFF)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}