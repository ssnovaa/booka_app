// ПУТЬ: lib/widgets/simple_player.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart';
import 'package:booka_app/screens/login_screen.dart';
import 'package:booka_app/screens/subscriptions_screen.dart';

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

  // 🔥 Локальний стан для слайдера
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _maybeSeekToInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
    audioProvider.onGuestFirstChapterEnd = () {
      final user = Provider.of<UserNotifier>(context, listen: false).user;
      final userType = getUserType(user);
      if (userType == UserType.guest && !_showedEndDialog) {
        _showedEndDialog = true;
        Future.microtask(() => _showAuthDialog(context));
      }
    };
  }

  @override
  void didUpdateWidget(SimplePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetDialogStateIfReplayed();

    // Если изменилась глава, сбрасываем состояние перетаскивания
    if (widget.selectedChapterId != oldWidget.selectedChapterId) {
      setState(() {
        _isDragging = false;
      });
    }
  }

  Future<void> _maybeSeekToInitial() async {
    if (!_didSeek && widget.initialPosition != null) {
      final provider = context.read<AudioPlayerProvider>();
      await Future.delayed(const Duration(milliseconds: 400));
      await provider.seek(Duration(seconds: widget.initialPosition!), persist: false);
      _didSeek = true;
    }
  }

  void _resetDialogStateIfReplayed() {
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

  Future<void> _skipSeconds(BuildContext context, int seconds) async {
    final provider = context.read<AudioPlayerProvider>();
    final effDur = _effectiveDuration(provider, provider.currentChapter);

    final basePos = _isDragging
        ? Duration(seconds: _dragValue.toInt())
        : provider.position;

    var target = basePos + Duration(seconds: seconds);

    if (target < Duration.zero) target = Duration.zero;
    if (effDur > Duration.zero && target > effDur) {
      target = effDur - const Duration(milliseconds: 500);
    }
    await provider.seek(target);
  }

  int _currentIndexInWidgetList(AudioPlayerProvider provider) {
    final currentId = provider.currentChapter?.id ?? widget.chapters.first.id;
    return widget.chapters.indexWhere((c) => c.id == currentId);
  }

  Future<void> _nextChapter(BuildContext context, UserType userType) async {
    if (mounted) setState(() => _isDragging = false);

    final provider = context.read<AudioPlayerProvider>();
    final idx = _currentIndexInWidgetList(provider);
    if (idx == -1) return;

    final nextIdx = idx + 1;
    if (nextIdx >= widget.chapters.length) return;

    if (userType == UserType.guest && nextIdx > 0) {
      _showAuthDialog(context);
      return;
    }

    await provider.seekChapter(nextIdx);
    widget.onChapterSelected(widget.chapters[nextIdx]);
  }

  Future<void> _previousChapter(BuildContext context, UserType userType) async {
    if (mounted) setState(() => _isDragging = false);

    final provider = context.read<AudioPlayerProvider>();
    final idx = _currentIndexInWidgetList(provider);
    if (idx == -1) return;

    if (idx == 0) {
      await provider.seek(const Duration(seconds: 0));
      return;
    }

    final prevIdx = idx - 1;

    if (userType == UserType.guest && prevIdx > 0) {
      _showAuthDialog(context);
      return;
    }

    await provider.seekChapter(prevIdx);
    widget.onChapterSelected(widget.chapters[prevIdx]);
  }

  void _showAuthDialog(BuildContext context) {
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
                          'Увійдіть, щоб отримати повний доступ до інших розділів.',
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
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
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
  }

  Duration _effectiveDuration(AudioPlayerProvider provider, Chapter? current) {
    final d = provider.duration;
    if (d > Duration.zero) return d;
    final meta = (current?.duration ?? 0);
    return meta > 0 ? Duration(seconds: meta) : Duration.zero;
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

    final effDuration = _effectiveDuration(provider, currentChapter);
    final hasDur = effDuration.inSeconds > 0;

    final double currentSeconds = _isDragging
        ? _dragValue
        : provider.position.inSeconds.toDouble();

    final double sliderMax = hasDur
        ? effDuration.inSeconds.toDouble()
        : (currentSeconds + 10).toDouble();

    final double sliderValue = currentSeconds.clamp(0.0, sliderMax);

    final connectivityMessage = provider.connectivityMessage;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (connectivityMessage != null)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          connectivityMessage,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),

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

              // 🔥 УЛУЧШЕННЫЙ СЛАЙДЕР (С ПУЗЫРЕМ И DIVISIONS)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6, // Линия чуть толще

                  // Большая зона нажатия (Overlay)
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 30.0),

                  // Настройка всплывающего пузыря
                  valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                  valueIndicatorColor: cs.primary,
                  valueIndicatorTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  showValueIndicator: ShowValueIndicator.always,
                ),
                child: Slider(
                  value: sliderValue,
                  min: 0.0,
                  max: sliderMax,
                  // 🔥 ВАЖНО: divisions включает пузырь
                  divisions: sliderMax > 0 ? sliderMax.toInt() : 1,
                  // Текст внутри пузыря
                  label: _formatDuration(Duration(seconds: sliderValue.floor())),

                  onChangeStart: (val) {
                    setState(() {
                      _isDragging = true;
                      _dragValue = val;
                    });
                  },
                  onChanged: (val) {
                    setState(() {
                      _dragValue = val;
                    });
                  },
                  onChangeEnd: (val) async {
                    setState(() => _dragValue = val);
                    await context.read<AudioPlayerProvider>().seek(Duration(seconds: val.floor()));
                    if (mounted) {
                      setState(() {
                        _isDragging = false;
                      });
                    }
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(Duration(seconds: sliderValue.floor())),
                        style: theme.textTheme.labelSmall),
                    Text(hasDur ? _formatDuration(effDuration) : '--:--',
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const _SpeedButton(),
                  IconButton(
                    tooltip: 'Попередній розділ',
                    onPressed: () => _previousChapter(context, userType),
                    icon: const Icon(Icons.skip_previous_rounded, size: 30),
                  ),
                  IconButton(
                    tooltip: '-10 с',
                    onPressed: () => _skipSeconds(context, -10),
                    icon: const Icon(Icons.replay_10_rounded, size: 28),
                  ),
                  Semantics(
                    label: provider.isPlaying ? 'Пауза' : 'Відтворити',
                    button: true,
                    child: _RoundPlayButton(
                      size: 64,
                      isPlaying: provider.isPlaying,
                      isBuffering: provider.isBuffering, // Статус буферизации
                      // 🔥 ИСПРАВЛЕНО: Передаем context в togglePlayback
                      onTap: () => provider.togglePlayback(context),
                    ),
                  ),
                  IconButton(
                    tooltip: '+10 с',
                    onPressed: () => _skipSeconds(context, 10),
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
                        child: Text.rich(
                          TextSpan(
                            style: theme.textTheme.bodySmall,
                            children: [
                              const TextSpan(text: 'Реклама: придбайте '),
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
                              const TextSpan(text: ' та слухайте без реклами!'),
                            ],
                          ),
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
                              : (isAvailable
                              ? cs.onSurface
                              : cs.onSurface.withOpacity(0.35)),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      enabled: isAvailable,
                      onTap: isAvailable
                          ? () async {
                        await context.read<AudioPlayerProvider>().seekChapter(index);
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
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final speed = context.watch<AudioPlayerProvider>().speed;
    final label =
    (speed % 1 == 0) ? '${speed.toStringAsFixed(0)}×' : '${speed.toStringAsFixed(2)}×';

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
  }
}

class _RoundPlayButton extends StatelessWidget {
  final double size;
  final bool isPlaying;
  final bool isBuffering; // Новое поле
  final VoidCallback onTap;

  const _RoundPlayButton({
    required this.size,
    required this.isPlaying,
    required this.isBuffering,
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
                  child: isBuffering
                  // 🔥 Если идет буферизация — крутим спиннер
                      ? const Padding(
                    padding: EdgeInsets.all(14.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7C4DFF)),
                    ),
                  )
                      : Icon(icon, size: iconSize, color: const Color(0xFF7C4DFF)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}