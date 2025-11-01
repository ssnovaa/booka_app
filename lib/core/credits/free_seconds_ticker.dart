// lib/core/credits/free_seconds_ticker.dart
// Комментарии — русские.
// Локальний тікер: раз в секунду зменшує freeSeconds, коли аудіо справді відтворюється.

import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

typedef BoolFn = bool Function();
typedef IntFn = int Function();
typedef VoidFn = void Function();

class FreeSecondsTicker {
  FreeSecondsTicker({
    required this.player,
    required this.getIsPaid,
    required this.getCurrentSeconds,
    required this.decOneSecond,
  });

  final AudioPlayer player;
  final BoolFn getIsPaid;
  final IntFn getCurrentSeconds;
  final VoidFn decOneSecond;

  Timer? _timer;
  bool _active = false;

  void start() {
    if (_active) return;
    _active = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();

  bool _isPlayingAudibly() {
    if (!player.playing) return false;
    final ps = player.processingState;
    if (ps == ProcessingState.idle ||
        ps == ProcessingState.loading ||
        ps == ProcessingState.buffering ||
        ps == ProcessingState.completed) {
      return false;
    }
    if (player.volume <= 0.0001) return false;
    if (player.speed <= 0.01) return false;
    return true;
  }

  void _onTick() {
    if (!_active) return;
    if (getIsPaid()) return;
    if (!_isPlayingAudibly()) return;

    final left = getCurrentSeconds();
    if (left <= 0) return;

    try {
      decOneSecond(); // дергаем UserNotifier → UI обновится сам
    } catch (e) {
      debugPrint('[FreeSecondsTicker] decOneSecond error: $e');
    }
  }
}
