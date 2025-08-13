import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chapter.dart';
import '../providers/audio_player_provider.dart';

class MiniPlayerWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final audioProvider = context.read<AudioPlayerProvider>();
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface.withOpacity(0.95),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.audiotrack_outlined, color: Colors.white70),
              const SizedBox(width: 12),
              _buildTrackInfo(context),
              _buildControls(context, audioProvider),
            ],
          ),
          const SizedBox(height: 4),
          _buildProgressBar(context, audioProvider),
        ],
      ),
    );
  }

  // Виджет для отображения информации о треке
  Widget _buildTrackInfo(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            bookTitle,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Виджет для кнопок управления
  Widget _buildControls(BuildContext context, AudioPlayerProvider audioProvider) {
    return Row(
      children: [
        // Кнопка Play/Pause обновляется независимо через StreamBuilder
        StreamBuilder<bool>(
          stream: audioProvider.playingStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () {
                if (isPlaying) {
                  audioProvider.pause();
                } else {
                  audioProvider.play();
                }
              },
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.expand_less_rounded, color: Colors.white, size: 32),
          onPressed: onExpand,
          tooltip: 'Открыть плеер',
        ),
      ],
    );
  }

  // Виджет для полосы прогресса и времени
  Widget _buildProgressBar(BuildContext context, AudioPlayerProvider audioProvider) {
    return StreamBuilder<Duration>(
      stream: audioProvider.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: audioProvider.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final progress = (duration.inSeconds > 0)
                ? (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
                : 0.0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  color: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    Text(_formatTime(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
