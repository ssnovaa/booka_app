// lib/widgets/mini_player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/audio/audio_controller_v2.dart';

class MiniPlayer extends StatelessWidget {
  final VoidCallback? onTap; // open full screen
  const MiniPlayer({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AudioControllerV2>();
    final p = ctrl.player;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.audiotrack),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ctrl.current?.title ?? 'Ничего не играет',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    StreamBuilder<Duration>(
                      stream: p.positionStream,
                      builder: (_, snap) {
                        final pos = snap.data ?? Duration.zero;
                        final dur = p.duration ?? Duration.zero;
                        final value = (dur.inMilliseconds == 0)
                            ? 0.0
                            : pos.inMilliseconds / dur.inMilliseconds;
                        return LinearProgressIndicator(value: value.clamp(0.0, 1.0));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: ctrl.toggle,
                icon: StreamBuilder<bool>(
                  stream: p.playingStream,
                  initialData: p.playing,
                  builder: (_, snap) => Icon(snap.data == true ? Icons.pause : Icons.play_arrow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
