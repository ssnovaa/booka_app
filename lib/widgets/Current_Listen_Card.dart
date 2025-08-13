// ПУТЬ: lib/widgets/current_listen_card.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_player_provider.dart';

class CurrentListenCard extends StatelessWidget {
  final VoidCallback onContinue;

  const CurrentListenCard({
    Key? key,
    required this.onContinue,
  }) : super(key: key);

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark
        ? Theme.of(context).cardColor
        : const Color(0xFFF0FBFF);

    // Получаем данные из AudioPlayerProvider
    return Consumer<AudioPlayerProvider>(
      builder: (context, audio, _) {
        final chapter = audio.currentChapter;
        final book = audio.currentBook;
        final position = audio.position.inSeconds;

        if (chapter == null || book == null) {
          // Заглушка, если ничего нет
          return Card(
            color: cardColor,
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.headphones, size: 50, color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Тут буде показано вашу останню прослухану книгу.\nПочніть слухати будь-яку аудіокнигу!',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final title = book.title.isNotEmpty ? book.title : 'Без назви';
        // ✅ КЛЮЧЕВАЯ ПРАВКА: берём миниатюру, иначе обложку
        final imageUrl = book.displayCoverUrl;
        final chapterTitle = chapter.title.isNotEmpty ? chapter.title : 'Невідомо';
        final totalDuration = chapter.duration ?? 0;

        double progress = 0.0;
        if (totalDuration > 0) {
          progress = (position / totalDuration).clamp(0.0, 1.0);
        }

        return Card(
          color: cardColor,
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (imageUrl.isNotEmpty)
                      ? Image.network(
                    imageUrl,
                    width: 90,
                    height: 130,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image, size: 70, color: Colors.grey),
                  )
                      : Container(
                    width: 90,
                    height: 130,
                    color: Colors.grey[300],
                    child: const Icon(Icons.book, size: 48, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Глава: $chapterTitle',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatDuration(position)} / ${_formatDuration(totalDuration)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFFFF4),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                          child: const Text('Продовжити'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
