import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chapter.dart';
import '../providers/audio_player_provider.dart';
import '../user_notifier.dart';
import '../models/user.dart';

class SimplePlayer extends StatefulWidget {
  final String bookTitle;
  final String author;
  final List<Chapter> chapters;
  final int? selectedChapterId;
  final Function(Chapter) onChapterSelected;
  final Chapter? initialChapter;
  final int? initialPosition; // <--- Новый параметр (секунды!)

  const SimplePlayer({
    super.key,
    required this.bookTitle,
    required this.author,
    required this.chapters,
    required this.selectedChapterId,
    required this.onChapterSelected,
    required this.initialChapter,
    this.initialPosition,         // <--- Новый параметр
  });

  @override
  State<SimplePlayer> createState() => _SimplePlayerState();
}

class _SimplePlayerState extends State<SimplePlayer> {
  bool _showedEndDialog = false;
  bool _didSeek = false; // <--- Чтобы seek не делался каждый rebuild

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Колбэк для AudioPlayerProvider: вызываем диалог при окончании главы
    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
    audioProvider.onGuestFirstChapterEnd = () {
      final user = Provider.of<UserNotifier>(context, listen: false).user;
      final userType = getUserType(user);
      if (userType == UserType.guest && !_showedEndDialog) {
        _showedEndDialog = true;
        Future.delayed(Duration.zero, () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Доступ ограничен'),
              content: const Text('Авторизуйтесь, чтобы получить доступ к другим главам.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushNamed('/login');
                  },
                  child: const Text('Войти'),
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

  @override
  void initState() {
    super.initState();
    _maybeSeekToInitial();
  }

  void _maybeSeekToInitial() async {
    // Сделать seek только 1 раз при запуске, если задана стартовая позиция
    if (!_didSeek && widget.initialPosition != null) {
      final provider = context.read<AudioPlayerProvider>();
      // Подожди пока плеер инициализируется (иначе может не сработать)
      await Future.delayed(const Duration(milliseconds: 400));
      provider.player.seek(Duration(seconds: widget.initialPosition!));
      _didSeek = true;
    }
  }

  void _resetDialogStateIfReplayed() {
    // Сброс флага, если пользователь начал слушать главу сначала
    final audioProvider = context.read<AudioPlayerProvider>();
    final user = Provider.of<UserNotifier>(context, listen: false).user;
    final userType = getUserType(user);
    final chapter = audioProvider.currentChapter;
    final position = audioProvider.position;

    if (userType == UserType.guest &&
        chapter != null &&
        chapter.order == 0 &&
        position.inSeconds < 3) {
      _showedEndDialog = false;
    }
  }

  void _changeSpeed(BuildContext context) {
    context.read<AudioPlayerProvider>().changeSpeed();
  }

  void _skipSeconds(BuildContext context, int seconds) {
    final provider = context.read<AudioPlayerProvider>();
    final newPosition = provider.position + Duration(seconds: seconds);
    provider.player.seek(newPosition);
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
    }
  }

  void _showAuthDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Доступ ограничен'),
          content: const Text('Авторизуйтесь, чтобы получить доступ к другим главам.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushNamed('/login');
              },
              child: const Text('Войти'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserNotifier>(context).user;
    final userType = getUserType(user);

    final provider = context.watch<AudioPlayerProvider>();
    final chapter = provider.currentChapter ?? (widget.initialChapter ?? widget.chapters.first);
    final position = provider.position;
    final duration = provider.duration;

    return Material(
      color: Colors.grey[900],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              Text(
                widget.bookTitle,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                widget.author,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Slider(
                value: position.inSeconds.clamp(0, duration.inSeconds > 0 ? duration.inSeconds : 1).toDouble(),
                max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                onChanged: (value) {
                  provider.player.seek(Duration(seconds: value.toInt()));
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: const TextStyle(color: Colors.white)),
                  Text(_formatDuration(duration), style: const TextStyle(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: () => _previousChapter(context, userType),
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () => _skipSeconds(context, -15),
                  ),
                  IconButton(
                    icon: Icon(
                      provider.isPlaying ? Icons.pause_circle : Icons.play_circle,
                      size: 48,
                      color: Colors.white,
                    ),
                    onPressed: () => provider.togglePlayback(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    onPressed: () => _skipSeconds(context, 15),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () => _nextChapter(context, userType),
                  ),
                ],
              ),
              if (userType == UserType.free) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.yellow[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.campaign, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Реклама: купите подписку и слушайте без рекламы!",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(color: Colors.white30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Выберите главу', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.chapters.length,
                  itemBuilder: (_, index) {
                    final ch = widget.chapters[index];
                    final isSelected = ch.id == chapter.id;
                    bool isAvailable = true;
                    if (userType == UserType.guest && index != 0) isAvailable = false;

                    return ListTile(
                      title: Text(
                        ch.title,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.amber
                              : isAvailable
                              ? Colors.white
                              : Colors.white24,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      enabled: isAvailable,
                      onTap: isAvailable
                          ? () {
                        context.read<AudioPlayerProvider>().seekChapter(index);
                        widget.onChapterSelected(ch);
                      }
                          : () {
                        _showAuthDialog(context);
                      },
                      trailing: !isAvailable
                          ? GestureDetector(
                        onTap: () => _showAuthDialog(context),
                        child: const Icon(Icons.lock, color: Colors.white24),
                      )
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
