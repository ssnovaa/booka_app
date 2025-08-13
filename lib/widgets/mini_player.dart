import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chapter.dart';
import '../providers/audio_player_provider.dart';
import '../user_notifier.dart'; // Для получения типа пользователя
import '../models/user.dart';

class MiniPlayerWidget extends StatefulWidget {
  final Chapter chapter;
  final String bookTitle;
  final VoidCallback onExpand;

  const MiniPlayerWidget({
    super.key,
    required this.chapter,
    required this.bookTitle,
    required this.onExpand,
  });

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget> {
  bool _showedEndDialog = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Важно! Назначаем callback, чтобы ловить окончание первой главы
    final audioProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
    audioProvider.onGuestFirstChapterEnd = () {
      final user = Provider.of<UserNotifier>(context, listen: false).user;
      final userType = getUserType(user);
      // --- ПОКАЗЫВАТЬ ДИАЛОГ ВСЕГДА, сброс флага отдельной функцией ---
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
                    Navigator.of(context).pushNamed('/login'); // Замени на свой путь к авторизации
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
  void didUpdateWidget(MiniPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetDialogStateIfReplayed();
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

  String formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioPlayerProvider>();
    final currentChapter = audioProvider.currentChapter;

    // Не показывать мини-плеер, если нет активной главы
    if (audioProvider.currentUrl == null || currentChapter == null) {
      return const SizedBox.shrink();
    }

    final position = audioProvider.position;
    final duration = audioProvider.duration;
    final progress = (duration.inMilliseconds > 0)
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.audiotrack, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentChapter.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.bookTitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  audioProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: audioProvider.togglePlayback,
              ),
              IconButton(
                icon: const Icon(Icons.expand_less, color: Colors.white),
                onPressed: widget.onExpand,
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: Colors.white,
            backgroundColor: Colors.grey[800],
            minHeight: 4,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatTime(position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(formatTime(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
