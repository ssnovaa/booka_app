// ПУТЬ: lib/widgets/simple_player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart';
import 'package:booka_app/screens/login_screen.dart';

/// Простий плеєр — список розділів + базове керування відтворенням.
/// Виправлено «сірий повзунок на максимумі»:
///  - використовуємо uiPosition з провайдера (з урахуванням drag-override)
///  - поки тривалість ще невідома, тимчасовий max = pos+1
class SimplePlayer extends StatefulWidget {
  final String bookTitle;
  final String author;
  final List<Chapter> chapters;
  final int? selectedChapterId;
  final Function(Chapter) onChapterSelected;
  final Chapter? initialChapter;
  final int? initialPosition; // секунди
  final Book book;

  const SimplePlayer({
    super.key,
    required this.bookTitle,
    required this.author,
    required this.chapters,
    required this.selectedChapterId,
    required this.onChapterSelected,
    required this.initialChapter,
    required this.book,
    this.initialPosition,
  });

  @override
  State<SimplePlayer> createState() => _SimplePlayerState();
}

class _SimplePlayerState extends State<SimplePlayer> {
  bool _showedEndDialog = false;
  bool _didSeek = false;

  @override
  void initState() {
    super.initState();
    _maybeSeekToInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 🔔 Колбек на завершення першого розділу для гостя
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
    // Скидаємо прапорець діалогу при повторному запуску першої глави
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
    final provider = context.read<AudioPlayerProvider>();
    if (!_samePlaylist(provider)) return;
    provider.changeSpeed();
  }

  Future<void> _skipSeconds(BuildContext context, int seconds) async {
    final provider = context.read<AudioPlayerProvider>();
    if (!_samePlaylist(provider)) return;

    final effDur = _effectiveDuration(provider, provider.currentChapter);

    var target = provider.uiPosition + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (effDur > Duration.zero && target > effDur) {
      target = effDur - const Duration(milliseconds: 500);
    }
    await provider.seek(target); // через провайдер — зберігаємо/синхронізуємо
  }

  // Поточний індекс у вихідному списку widget.chapters (за id з провайдера)
  int _currentIndexInWidgetList(AudioPlayerProvider provider) {
    final currentId = provider.currentChapter?.id ?? widget.chapters.first.id;
    return widget.chapters.indexWhere((c) => c.id == currentId);
  }

  bool _samePlaylist(AudioPlayerProvider provider) {
    if (provider.currentBook?.id != widget.book.id) return false;
    if (provider.chapters.length != widget.chapters.length) return false;
    for (var i = 0; i < widget.chapters.length; i++) {
      if (provider.chapters[i].id != widget.chapters[i].id) return false;
    }
    return true;
  }

  int _selectedChapterIndex() {
    if (widget.selectedChapterId != null) {
      final idx = widget.chapters.indexWhere((c) => c.id == widget.selectedChapterId);
      if (idx != -1) return idx;
    }
    return 0;
  }

  Future<void> _ensureThisBookAndPlay(AudioPlayerProvider provider) async {
    final startIndex = _selectedChapterIndex();

    await provider.pause();
    await provider.setChapters(
      widget.chapters,
      startIndex: startIndex,
      bookTitle: widget.bookTitle,
      artist: widget.author,
      coverUrl: widget.chapters[startIndex].coverUrl,
      book: widget.book,
    );

    await provider.seekChapter(startIndex, position: Duration.zero, persist: false);
    await provider.play();
  }

  Future<void> _nextChapter(BuildContext context, UserType userType) async {
    final provider = context.read<AudioPlayerProvider>();
    if (!_samePlaylist(provider)) return;

    final idx = _currentIndexInWidgetList(provider);
    if (idx == -1) return;

    final nextIdx = idx + 1;
    if (nextIdx >= widget.chapters.length) return;

    // Гість — тільки перша глава
    if (userType == UserType.guest && nextIdx > 0) {
      _showAuthDialog(context);
      return;
    }

    await provider.seekChapter(nextIdx);
    widget.onChapterSelected(widget.chapters[nextIdx]);
  }

  Future<void> _previousChapter(BuildContext context, UserType userType) async {
    final provider = context.read<AudioPlayerProvider>();
    if (!_samePlaylist(provider)) return;

    final idx = _currentIndexInWidgetList(provider);
    if (idx == -1) return;

    if (idx == 0) {
      // Якщо вже перша — переміститись на початок
      await provider.seek(const Duration(seconds: 0));
      return;
    }

    final prevIdx = idx - 1;

    // Гість — дозволяємо перейти лише на нульовий індекс
    if (userType == UserType.guest && prevIdx > 0) {
      _showAuthDialog(context);
      return;
    }

    await provider.seekChapter(prevIdx);
    widget.onChapterSelected(widget.chapters[prevIdx]);
  }

  /// 🔐 Адаптивне попередження про доступ (bottom-sheet)
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
        // Адаптивність шрифтів + обмеження ширини для планшетів/великих екранів
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
                          'Увійдіть, щоб отримати повний доступ до інших розділів і синхронізації прогресу.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).maybePop();
                          // Переходимо на екран логіну через rootNavigator
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

  // Ефективна тривалість: плеєрна або з метаданих глави (щоб не було "сірої" шкали)
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
    final samePlaylist = _samePlaylist(provider);

    final fallbackChapter = widget.initialChapter ??
        (widget.selectedChapterId != null
            ? widget.chapters.firstWhere(
                (c) => c.id == widget.selectedChapterId,
                orElse: () => widget.chapters.first,
              )
            : widget.chapters.first);

    final currentChapter =
        samePlaylist ? (provider.currentChapter ?? fallbackChapter) : fallbackChapter;

    // Позиція з урахуванням drag-override, щоб UI був стабільним під час перетягування
    final position = samePlaylist ? provider.uiPosition : Duration.zero;

    // Ефективна тривалість
    final effDuration = samePlaylist
        ? _effectiveDuration(provider, currentChapter)
        : Duration(seconds: currentChapter.duration ?? 0);
    final hasDur = effDuration.inSeconds > 0;

    // Значення слайдера
    // Поки немає тривалості — ставимо тимчасовий max, щоб повзунок не був «сірим на максимумі»
    final double sliderMax = hasDur
        ? effDuration.inSeconds.toDouble()
        : (position.inSeconds + 1).clamp(1, 24 * 60 * 60).toDouble();
    final double sliderValue =
    position.inSeconds.toDouble().clamp(0.0, sliderMax);

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
                  onChangeStart: samePlaylist
                      ? (_) => context.read<AudioPlayerProvider>().seekDragStart()
                      : null,
                  onChanged: samePlaylist
                      ? (v) => context
                          .read<AudioPlayerProvider>()
                          .seekDragUpdate(Duration(seconds: v.floor()))
                      : null,
                  onChangeEnd: samePlaylist
                      ? (v) => context
                          .read<AudioPlayerProvider>()
                          .seekDragEnd(Duration(seconds: v.floor()))
                      : null,
                ),
              ),

              // Таймінги
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position), style: theme.textTheme.labelSmall),
                    Text(hasDur ? _formatDuration(effDuration) : '--:--',
                        style: theme.textTheme.labelSmall),
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
                    label: (samePlaylist && provider.isPlaying) ? 'Пауза' : 'Відтворити',
                    button: true,
                    child: _RoundPlayButton(
                      size: 64,
                      isPlaying: samePlaylist && provider.isPlaying,
                      onTap: () async {
                        if (!samePlaylist) {
                          await _ensureThisBookAndPlay(provider);
                          return;
                        }
                        await provider.togglePlayback();
                      },
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
