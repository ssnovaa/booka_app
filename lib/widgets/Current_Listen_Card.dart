import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../providers/audio_player_provider.dart';

class CurrentListenCard extends StatelessWidget {
  final VoidCallback? onContinue;

  const CurrentListenCard({
    super.key,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    // Используем Consumer, чтобы реагировать на смену книги/главы
    return Consumer<AudioPlayerProvider>(
      builder: (context, audio, _) {
        final book = audio.currentBook;
        final chapter = audio.currentChapter;

        if (book == null || chapter == null) {
          return _buildPlaceholder(context);
        }

        return _buildCardContent(context, book, chapter, audio);
      },
    );
  }

  // Виджет-заглушка, когда ничего не проигрывается
  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.blue.withOpacity(0.05),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 90,
              height: 130,
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.headphones_outlined, size: 50, color: Colors.grey.withOpacity(0.5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Начните слушать любую аудиокнигу, и ваш прогресс появится здесь.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Основной виджет карточки, который не перестраивается каждую секунду
  Widget _buildCardContent(BuildContext context, Book book, Chapter chapter, AudioPlayerProvider audio) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final imageUrl = book.displayCoverUrl;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onContinue,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: (imageUrl != null && imageUrl.isNotEmpty)
                    ? Image.network(
                  imageUrl,
                  width: 90,
                  height: 130,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 70, color: Colors.grey),
                )
                    : Container(
                  width: 90,
                  height: 130,
                  color: isDark ? Colors.white10 : Colors.black12,
                  child: const Icon(Icons.book, size: 48, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      book.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Глава: ${chapter.title}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Виджет прогресса, который обновляется независимо
                    _PlayerProgress(audioProvider: audio),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onContinue,
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: const Text('Продолжить'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Этот виджет будет перестраиваться каждую секунду, не затрагивая остальную часть карточки
class _PlayerProgress extends StatelessWidget {
  final AudioPlayerProvider audioProvider;

  const _PlayerProgress({required this.audioProvider});

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioProvider.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: audioProvider.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            double progress = 0.0;
            if (duration.inSeconds > 0) {
              progress = (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
