import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chapter.dart';
import '../models/user.dart';
import '../providers/audio_player_provider.dart';
import '../user_notifier.dart';

class SimplePlayer extends StatelessWidget {
  final String bookTitle;
  final String author;
  final List<Chapter> chapters;

  const SimplePlayer({
    super.key,
    required this.bookTitle,
    required this.author,
    required this.chapters,
  });

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.read<AudioPlayerProvider>();
    final userType = context.watch<UserNotifier>().userType;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildTrackInfo(context),
              const SizedBox(height: 24),
              _buildProgressBar(context, audioProvider),
              const SizedBox(height: 16),
              _buildControls(context, audioProvider),
              const SizedBox(height: 24),
              const Divider(),
              _buildChapterListHeader(context),
              Expanded(
                child: _buildChapterList(context, audioProvider, userType),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 48), // Распорка для центрирования
        Text(
          'Сейчас играет',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildTrackInfo(BuildContext context) {
    // Этот виджет будет перестраиваться только при смене главы
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
              author,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[500]),
            ),
          ],
        );
      },
    );
  }

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
                    audioProvider.seek(Duration(seconds: value.toInt()));
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(position), style: Theme.of(context).textTheme.bodySmall),
                    Text(_formatTime(duration), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, AudioPlayerProvider audioProvider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10_rounded, size: 32),
          onPressed: () => audioProvider.seek(audioProvider.player.position - const Duration(seconds: 10)),
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
              onPressed: () => isPlaying ? audioProvider.pause() : audioProvider.play(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.forward_10_rounded, size: 32),
          onPressed: () => audioProvider.seek(audioProvider.player.position + const Duration(seconds: 10)),
        ),
      ],
    );
  }

  Widget _buildChapterListHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        'Главы',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildChapterList(BuildContext context, AudioPlayerProvider audioProvider, UserType userType) {
    // Этот виджет будет перестраиваться только при смене главы
    return Consumer<AudioPlayerProvider>(
      builder: (context, audio, child) {
        return ListView.builder(
          itemCount: chapters.length,
          itemBuilder: (_, index) {
            final chapter = chapters[index];
            final isSelected = chapter.id == audio.currentChapter?.id;
            bool isAvailable = true;
            if (userType == UserType.guest && index != 0) isAvailable = false;
            if (userType == UserType.free && index >= 3) isAvailable = false;

            return ListTile(
              title: Text(
                chapter.title,
                style: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.primary : (isAvailable ? null : Colors.grey),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              enabled: isAvailable,
              onTap: isAvailable
                  ? () => audio.seekToChapter(index)
                  : () => _showAuthDialog(context),
              trailing: isAvailable
                  ? (isSelected ? Icon(Icons.volume_up_rounded, color: Theme.of(context).colorScheme.primary) : null)
                  : const Icon(Icons.lock_outline_rounded, color: Colors.grey),
            );
          },
        );
      },
    );
  }

  void _showAuthDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступ ограничен'),
        content: const Text('Авторизуйтесь или оформите подписку, чтобы получить доступ к другим главам.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
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
  }

  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
