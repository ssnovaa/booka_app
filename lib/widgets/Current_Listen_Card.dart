// ПУТЬ: lib/widgets/current_listen_card.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/audio_player_provider.dart';
import '../core/network/image_cache.dart'; // BookaImageCacheManager

class CurrentListenCard extends StatelessWidget {
  final VoidCallback onContinue;

  const CurrentListenCard({
    Key? key,
    required this.onContinue,
  }) : super(key: key);

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    // Если хочешь показывать часы при >60 мин — скажи, добавлю формат 1:23:45
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark
        ? Theme.of(context).cardColor
        : const Color(0xFFF0FBFF);

    return Consumer<AudioPlayerProvider>(
      builder: (context, audio, _) {
        final chapter = audio.currentChapter;
        final book = audio.currentBook;
        final position = audio.position.inSeconds;

        if (chapter == null || book == null) {
          // Заглушка, когда ещё ничего не слушали
          return Card(
            color: cardColor,
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  _CoverPlaceholder(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Тут буде показано вашу останню прослухану книгу.\nПочніть слухати будь-яку аудіокнигу!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final title = book.title.isNotEmpty ? book.title : 'Без назви';
        // БЕРЕМ миниатюру, иначе обложку — предполагается, что displayCoverUrl уже абсолютный URL
        final imageUrl = book.displayCoverUrl;
        final chapterTitle = chapter.title.isNotEmpty ? chapter.title : 'Невідомо';
        final total = chapter.duration ?? 0;

        final double progress = (total > 0)
            ? (position / total).clamp(0.0, 1.0)
            : 0.0;

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
                      ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    cacheManager: BookaImageCacheManager.instance,
                    width: 90,
                    height: 130,
                    fit: BoxFit.cover,
                    // Чтобы не было «мигания» при подмене URL:
                    useOldImageOnUrlChange: true,
                    placeholder: (ctx, _) => const _CoverShimmer(),
                    errorWidget: (ctx, _, __) =>
                    const Icon(Icons.broken_image, size: 70, color: Colors.grey),
                  )
                      : const _CoverPlaceholder(),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Глава: $chapterTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: total > 0 ? progress : null),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatDuration(position)} / ${_formatDuration(total)}',
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
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

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 130,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.book, size: 48, color: Colors.grey),
        ),
      ),
    );
  }
}

class _CoverShimmer extends StatelessWidget {
  const _CoverShimmer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 90,
      height: 130,
      child: ColoredBox(color: Colors.black12),
    );
  }
}
