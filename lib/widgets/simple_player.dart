import 'package:booka_app/screens/login_screen.dart';
// lib/widgets/simple_player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart';

/// Простий плеєр — список розділів + базове керування відтворенням.
/// Тексти інтерфейсу та коментарі українською.
class SimplePlayer extends StatefulWidget {
  final String bookTitle;
  final String author;
  final List<Chapter> chapters;
  final int? selectedChapterId;
  final Function(Chapter) onChapterSelected;
  final Chapter? initialChapter;
  final int? initialPosition; // секунди

  const SimplePlayer({
    super.key,
    required this.bookTitle,
    required this.author,
    required this.chapters,
    required this.selectedChapterId,
    required this.onChapterSelected,
    required this.initialChapter,
    this.initialPosition,
  });

  @override
  State<SimplePlayer> createState() => _SimplePlayerState();
}

class _SimplePlayerState extends State<SimplePlayer> {
  bool _showedEndDialog = false;
  bool _didSeek = false;

  double? _dragValueSecs; // тимчасове значення слайдера під час перетягування

  @override
  void initState() {
    super.initState();
    _maybeSeekToInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Колбек на завершення першого розділу для гостя
    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
    audioProvider.onGuestFirstChapterEnd = () {
      final user = Provider.of<UserNotifier>(context, listen: false).user;
      final userType = getUserType(user);
      if (userType == UserType.guest && !_showedEndDialog) {
        _showedEndDialog = true;
        Future.microtask(() {
          showDialog(
            context: context,
            useRootNavigator: true,
            builder: (ctx) => AlertDialog(
              title: const Text('Доступ обмежено'),
              content: const Text('Увійдіть, щоб отримати доступ до інших розділів.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Скасувати'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Navigator.of(ctx, rootNavigator: true).push(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      });
                    });
                  },
                  child: const Text('Увійти'),
                ),
              ],
            ),
          );
        });
      }
    };
  }

  @override
  void didUpdateWidget(SimplePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetDialogStateIfReplayed();
  }

  Future<void> _maybeSeekToInitial() async {
    // Один раз перемістимо позицію на початкову, якщо вона задана
    if (!_didSeek && widget.initialPosition != null) {
      final provider = context.read<AudioPlayerProvider>();
      // даємо джерелу трохи часу на підготовку
      await Future.delayed(const Duration(milliseconds: 400));
      await provider.seek(Duration(seconds: widget.initialPosition!), persist: false);
      _didSeek = true;
    }
  }

  void _resetDialogStateIfReplayed() {
    // Скидаємо флаг діалогу при повторному запуску першої глави
    final audioProvider = context.read<AudioPlayerProvider>();
    final user = Provider.of<UserNotifier>(context, listen: false).user;
    final userType = getUserType(user);
    final chapter = audioProvider.currentChapter;
    final position = audioProvider.position;

    if (userType == UserType.guest &&
        chapter != null &&
        (chapter.order <= 1) &&
        position.inSeconds < 3) {
      _showedEndDialog = false;
    }
  }

  void _changeSpeed(BuildContext context) {
    context.read<AudioPlayerProvider>().changeSpeed();
  }

  Future<void> _skipSeconds(BuildContext context, int seconds) async {
    final provider = context.read<AudioPlayerProvider>();
    final dur = provider.duration;

    var target = provider.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;

    await provider.seek(target); // через провайдер — зберігаємо/синхронізуємо
  }

  void _nextChapter(BuildContext context, UserType userType) {
    final provider = context.read<AudioPlayerProvider>();
    final idx = provider.player.currentIndex ?? 0;
    if (idx < widget.chapters.length - 1) {
      bool canPlayNext = true;
      if (userType == UserType.guest && idx + 1 > 0) {
        canPlayNext = false;
      }
      if (canPlayNext) {
        provider.seekChapter(idx + 1);
        widget.onChapterSelected(widget.chapters[idx + 1]);
      } else {
        _showAuthDialog(context);
      }
    }
  }

  void _previousChapter(BuildContext context, UserType userType) {
    final provider = context.read<AudioPlayerProvider>();
    final idx = provider.player.currentIndex ?? 0;
    if (idx > 0) {
      bool canPlayPrev = true;
      if (userType == UserType.guest && idx - 1 > 0) {
        canPlayPrev = false;
      }
      if (canPlayPrev) {
        provider.seekChapter(idx - 1);
        widget.onChapterSelected(widget.chapters[idx - 1]);
      } else {
        _showAuthDialog(context);
      }
    } else {
      // Якщо вже перша — переміститись на початок
      provider.seek(const Duration(seconds: 0));
    }
  }

  void _showAuthDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Доступ обмежено'),
          content: const Text('Увійдіть, щоб отримати доступ до інших розділів.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Скасувати'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.of(ctx, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  });
                });
              },
              child: const Text('Увійти'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = Provider.of<UserNotifier>(context).user;
    final userType = getUserType(user);

    final provider = context.watch<AudioPlayerProvider>();
    final currentChapter =
        provider.currentChapter ?? (widget.initialChapter ?? widget.chapters.first);

    final position = provider.position;
    final duration = provider.duration;

    // Значення слайдера: показуємо тимчасове під час перетягування
    final double sliderMax =
    duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final double rawValue = (_dragValueSecs ?? position.inSeconds.toDouble());
    final double sliderValue = rawValue.clamp(0.0, sliderMax).toDouble();

    final displayedPos = Duration(
      seconds: (_dragValueSecs ?? position.inSeconds.toDouble()).toInt(),
    );

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Заголовки
              Text(
                currentChapter.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.8),
                ),
              ),
              Text(
                widget.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),

              const SizedBox(height: 12),

              // Слайдер позиції
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: sliderValue,
                  min: 0.0,
                  max: sliderMax,
                  onChangeStart: (v) => setState(() => _dragValueSecs = v),
                  onChanged: (v) => setState(() => _dragValueSecs = v),
                  onChangeEnd: (v) async {
                    setState(() => _dragValueSecs = null);
                    await context
                        .read<AudioPlayerProvider>()
                        .seek(Duration(seconds: v.toInt()));
                  },
                ),
              ),

              // Таймінги
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(displayedPos), style: theme.textTheme.labelSmall),
                    Text(_formatDuration(duration), style: theme.textTheme.labelSmall),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Кнопки керування
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Кнопка зміни швидкості
                  const _SpeedButton(),

                  IconButton(
                    tooltip: 'Попередній розділ',
                    onPressed: () => _previousChapter(context, userType),
                    icon: const Icon(Icons.skip_previous_rounded, size: 30),
                  ),
                  IconButton(
                    tooltip: '-15 с',
                    onPressed: () => _skipSeconds(context, -15),
                    icon: const Icon(Icons.replay_10_rounded, size: 28),
                  ),

                  // Play / Pause
                  Semantics(
                    label: provider.isPlaying ? 'Пауза' : 'Відтворити',
                    button: true,
                    child: _RoundPlayButton(
                      size: 64,
                      isPlaying: provider.isPlaying,
                      onTap: provider.togglePlayback,
                    ),
                  ),

                  IconButton(
                    tooltip: '+15 с',
                    onPressed: () => _skipSeconds(context, 15),
                    icon: const Icon(Icons.forward_10_rounded, size: 28),
                  ),
                  IconButton(
                    tooltip: 'Наступний розділ',
                    onPressed: () => _nextChapter(context, userType),
                    icon: const Icon(Icons.skip_next_rounded, size: 30),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Банер для free (каталог доступний, але з рекламою)
              if (userType == UserType.free)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.tertiary.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign, color: cs.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Реклама: придбайте підписку та слухайте без реклами!",
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

              Divider(color: cs.outlineVariant.withOpacity(0.35)),

              Align(
                alignment: Alignment.centerLeft,
                child: Text('Оберіть розділ', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: 8),

              // Список розділів
              Expanded(
                child: ListView.builder(
                  itemCount: widget.chapters.length,
                  itemBuilder: (_, index) {
                    final ch = widget.chapters[index];
                    final isSelected = ch.id == currentChapter.id;

                    bool isAvailable = true;
                    if (userType == UserType.guest && index != 0) {
                      isAvailable = false;
                    }

                    return ListTile(
                      dense: true,
                      title: Text(
                        ch.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? cs.primary
                              : (isAvailable ? cs.onSurface : cs.onSurface.withOpacity(0.35)),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      enabled: isAvailable,
                      onTap: isAvailable
                          ? () {
                        context.read<AudioPlayerProvider>().seekChapter(index);
                        widget.onChapterSelected(ch);
                      }
                          : () => _showAuthDialog(context),
                      trailing: !isAvailable
                          ? Icon(Icons.lock, color: cs.onSurface.withOpacity(0.35))
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Кнопка швидкості з поточним значенням (1×, 1.25× ...).
class _SpeedButton extends StatelessWidget {
  const _SpeedButton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final audio = context.read<AudioPlayerProvider>();

    return StreamBuilder<double>(
      // just_audio: speedStream є у player
      stream: audio.player.speedStream,
      initialData: audio.player.speed,
      builder: (context, snap) {
        final sp = (snap.data ?? 1.0);
        final label = (sp % 1 == 0) ? '${sp.toStringAsFixed(0)}×' : '${sp.toStringAsFixed(2)}×';

        return InkWell(
          onTap: () => context.read<AudioPlayerProvider>().changeSpeed(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.25)),
            ),
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
            ),
          ),
        );
      },
    );
  }
}

/// Кругла кнопка play/pause з градієнтним кільцем.
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
    final iconSize = size * 0.56;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFF48FB1),
                    Color(0xFF7C4DFF),
                    Color(0xFF448AFF),
                    Color(0xFF00BCD4),
                    Color(0xFFF48FB1),
                  ],
                  stops: [0.0, 0.33, 0.66, 0.85, 1.0],
                ),
              ),
              child: Center(
                child: Container(
                  width: size - 10,
                  height: size - 10,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize, color: const Color(0xFF7C4DFF)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
