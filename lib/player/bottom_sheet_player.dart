// lib/player/bottom_sheet_player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_player_provider.dart';
import '../models/chapter.dart';

class BottomSheetPlayer {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PlayerContent(),
    );
  }
}

class _PlayerContent extends StatelessWidget {
  const _PlayerContent();

  String _formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final book = audio.currentBook;
    final currentChapter = audio.currentChapter;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Хендл сверху
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Картинка книги
          if (book?.coverUrl != null && book!.coverUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                book.coverUrl!,
                width: 150,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),

          const SizedBox(height: 12),

          // Название книги и главы
          Text(
            book?.title ?? 'Без названия',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (currentChapter != null)
            Text(
              currentChapter.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),

          const SizedBox(height: 12),

          // Прогресс-бар
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatTime(audio.position)),
              Text(_formatTime(audio.duration)),
            ],
          ),
          Slider(
            value: audio.position.inSeconds.toDouble(),
            min: 0,
            max: audio.duration.inSeconds.toDouble(),
            onChanged: (value) {
              audio.seekTo(Duration(seconds: value.toInt()));
            },
          ),

          const SizedBox(height: 8),

          // Кнопки управления
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 32),
                onPressed: audio.previousChapter,
              ),
              IconButton(
                icon: Icon(
                  audio.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  size: 48,
                ),
                onPressed: audio.togglePlayback,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 32),
                onPressed: audio.nextChapter,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Список глав
          if (audio.chapters.isNotEmpty)
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: audio.chapters.length,
                itemBuilder: (context, index) {
                  final ch = audio.chapters[index];
                  final isCurrent = ch.id == currentChapter?.id;
                  return ListTile(
                    title: Text(
                      ch.title,
                      style: TextStyle(
                        fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () => audio.seekChapter(index),
                    selected: isCurrent,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
