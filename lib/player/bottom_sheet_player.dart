import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_player_provider.dart';

class BottomSheetPlayer {
  // Статический метод для удобного вызова
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Позволяет занимать > 50% экрана
      backgroundColor: Colors.transparent,
      builder: (_) => const _PlayerContent(),
    );
  }
}

// Основной виджет, который отображается в BottomSheet
class _PlayerContent extends StatelessWidget {
  const _PlayerContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioProvider = context.read<AudioPlayerProvider>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHandle(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildCoverArt(context, audioProvider.currentBook?.displayCoverUrl),
                  const SizedBox(height: 24),
                  _buildTrackInfo(context),
                  const SizedBox(height: 16),
                  _buildProgressBar(context, audioProvider),
                  const SizedBox(height: 8),
                  _buildControls(context, audioProvider),
                  const SizedBox(height: 24),
                  _buildChapterList(context, audioProvider),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Ручка для закрытия
  Widget _buildHandle(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(2.5),
      ),
    );
  }

  // Обложка книги
  Widget _buildCoverArt(BuildContext context, String? imageUrl) {
    final size = MediaQuery.of(context).size.width * 0.6;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: (imageUrl != null && imageUrl.isNotEmpty)
          ? Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60),
      )
          : Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: const Icon(Icons.music_note, size: 60, color: Colors.white54),
      ),
    );
  }

  // Информация о треке (обновляется при смене главы)
  Widget _buildTrackInfo(BuildContext context) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, audio, child) {
        return Column(
          children: [
            Text(
              audio.currentChapter?.title ?? 'Неизвестная глава',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              audio.currentBook?.title ?? 'Неизвестная книга',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[500]),
            ),
          ],
        );
      },
    );
  }

  // Полоса прогресса и время (обновляются по стриму)
  Widget _buildProgressBar(BuildContext context, AudioPlayerProvider audioProvider) {
    return StreamBuilder<Duration>(
      stream: audioProvider.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: audioProvider.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            return Column(
              children: [
                Slider(
                  value: position.inSeconds.toDouble().clamp(0.0, duration.inSeconds.toDouble()),
                  max: duration.inSeconds.toDouble().isFinite ? duration.inSeconds.toDouble() : 1.0,
                  onChanged: (value) {
                    // ИСПРАВЛЕНИЕ: используем правильный метод seek
                    audioProvider.seek(Duration(seconds: value.toInt()));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(position), style: Theme.of(context).textTheme.bodySmall),
                      Text(_formatTime(duration), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Кнопки управления (обновляются по стриму)
  Widget _buildControls(BuildContext context, AudioPlayerProvider audioProvider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 36),
          // ИСПРАВЛЕНИЕ: используем прямой доступ к плееру
          onPressed: audioProvider.player.seekToPrevious,
        ),
        StreamBuilder<bool>(
          stream: audioProvider.playingStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              // ИСПРАВЛЕНИЕ: используем правильные методы play/pause
              onPressed: () => isPlaying ? audioProvider.pause() : audioProvider.play(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 36),
          // ИСПРАВЛЕНИЕ: используем прямой доступ к плееру
          onPressed: audioProvider.player.seekToNext,
        ),
      ],
    );
  }

  // Список глав
  Widget _buildChapterList(BuildContext context, AudioPlayerProvider audioProvider) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, audio, child) {
        return ExpansionTile(
          title: const Text('Список глав'),
          children: audio.chapters.asMap().entries.map((entry) {
            final index = entry.key;
            final chapter = entry.value;
            final isSelected = chapter.id == audio.currentChapter?.id;

            return ListTile(
              title: Text(chapter.title),
              selected: isSelected,
              // ИСПРАВЛЕНИЕ: используем правильный метод seekToChapter
              onTap: () => audio.seekToChapter(index),
              trailing: isSelected ? const Icon(Icons.play_arrow, color: Colors.green) : null,
            );
          }).toList(),
        );
      },
    );
  }

  String _formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
