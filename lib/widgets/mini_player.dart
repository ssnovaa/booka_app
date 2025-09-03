// lib/widgets/mini_player.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';

class MiniPlayerWidget extends StatefulWidget {
  final Chapter chapter;
  final String bookTitle;
  final String? coverUrl; // міні-обкладинка
  final VoidCallback onExpand;

  const MiniPlayerWidget({
    super.key,
    required this.chapter,
    required this.bookTitle,
    required this.onExpand,
    this.coverUrl,
  });

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget> {
  bool _showedEndDialog = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Колбек на завершення першого розділу у гостьовому режимі
    final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
    audio.onGuestFirstChapterEnd = () {
      final isGuest = Provider.of<UserNotifier>(context, listen: false).isGuest;
      if (!isGuest || _showedEndDialog) return;

      _showedEndDialog = true;
      Future.microtask(() {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Доступ обмежено'),
            content: const Text('Авторизуйтеся, щоб отримати доступ до інших розділів.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Скасувати'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamed('/login');
                },
                child: const Text('Увійти'),
              ),
            ],
          ),
        );
      });
    };
  }

  // Формат часу mm:ss
  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  // Тап по прогрес-бару → seek
  void _seekByTap(BuildContext context, TapDownDetails details, double width) {
    final audio = context.read<AudioPlayerProvider>();
    final dur = audio.duration;
    if (dur == Duration.zero) return;

    final dx = details.localPosition.dx.clamp(0, width);
    final ratio = dx / width;
    final target = Duration(milliseconds: (dur.inMilliseconds * ratio).round());
    audio.seekTo(target);
  }

  // Відкрити повний плеєр або показати гостевий екран
  void _handleExpandTap() {
    final isGuest = context.read<UserNotifier>().isGuest;
    if (isGuest) {
      _showGuestSheet();
    } else {
      widget.onExpand();
    }
  }

  void _showGuestSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 28),
            const SizedBox(height: 8),
            const Text('Доступ обмежено', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Увійдіть, щоб мати доступ до всіх розділів і повноцінного плеєра.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Скасувати'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).pushNamed('/login');
                    },
                    child: const Text('Увійти'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final audio = context.watch<AudioPlayerProvider>();
    final currentChapter = audio.currentChapter;

    // Якщо нічого не відтворюється — не показуємо міні-плеєр
    if (audio.currentUrl == null || currentChapter == null) {
      return const SizedBox.shrink();
    }

    final pos = audio.position;
    final dur = audio.duration;
    final progress = (dur.inMilliseconds > 0)
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final isGuest = context.select<UserNotifier, bool>((n) => n.isGuest);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleExpandTap,
          onVerticalDragUpdate: (d) {
            if (d.delta.dy < -8) _handleExpandTap(); // свайп догори → розгорнути
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Фон з блюром (glass-card)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface.withOpacity(0.88),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),

                // Контент
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Хендл-підказка (пилюля)
                      Container(
                        width: 28,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      Row(
                        children: [
                          _CoverThumb(url: widget.coverUrl),
                          const SizedBox(width: 12),

                          // Заголовки
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

                          // Кнопка play/pause «як у нижньому барі» (менша)
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

                          // Кнопка розгортання (із замком для гостя)
                          Semantics(
                            label: 'Розгорнути плеєр',
                            button: true,
                            child: IconButton(
                              iconSize: 28,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(), // без мінімальних 48×48
                              onPressed: _handleExpandTap,
                              icon: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.keyboard_arrow_up),
                                  if (isGuest)
                                    const Positioned(
                                      right: -6,
                                      top: -2,
                                      child: Icon(Icons.lock, size: 14),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Прогрес (тап → seek)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => _seekByTap(context, d, constraints.maxWidth),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: progress,
                                backgroundColor: cs.onSurface.withOpacity(0.08),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 6),

                      // Таймінги
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(pos),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                          Text(
                            _fmt(dur),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
          color: cs.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.audiotrack, color: cs.primary),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: cs.primary.withOpacity(0.12),
          child: Icon(Icons.audiotrack, color: cs.primary),
        ),
      ),
    );
  }
}

/// Кругла кнопка «як у нижньому барі», але меншого розміру і без невидимих полів.
/// Зовнішнє кільце — градієнт, всередині — біле коло з іконкою play/pause.
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
                    Color(0xFFF48FB1), // pink
                    Color(0xFF7C4DFF), // deep purple
                    Color(0xFF448AFF), // blue
                    Color(0xFF00BCD4), // cyan
                    Color(0xFFF48FB1),
                  ],
                  stops: [0.0, 0.33, 0.66, 0.85, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: size - 8, // товщина кільця ~4dp
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
