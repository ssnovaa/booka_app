// lib/core/credits/credits_consumer.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class CreditsConsumer {
  final Dio dio;
  final AudioPlayer player;
  final bool Function() isPaid;        // true -> списывать не нужно
  final bool Function() isFreeUser;    // true -> free (и не в ad-mode)
  final void Function(int secondsLeft, int minutesLeft)? onBalanceUpdated;
  final VoidCallback? onExhausted;

  final Duration tickInterval;

  Timer? _timer;
  Duration _lastPosition = Duration.zero;
  bool _active = false;
  bool _exhausted = false;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _procSub;

  final _exhaustedCtr = StreamController<void>.broadcast();
  Stream<void> get exhaustedStream => _exhaustedCtr.stream;

  CreditsConsumer({
    required this.dio,
    required this.player,
    required this.isPaid,
    required this.isFreeUser,
    this.onBalanceUpdated,
    this.onExhausted,
    this.tickInterval = const Duration(seconds: 20),
  }) {
    _playingSub = player.playingStream.listen((playing) async {
      // Блокировать можно ТОЛЬКО для free без ad-mode.
      if (playing && _exhausted && !isPaid() && isFreeUser()) {
        await _forcePauseEverywhere();
        return;
      }
      if (playing && _isPlayingAudibly()) {
        _ensureStarted();
      } else {
        _ensureStopped();
      }
    });

    _procSub = player.processingStateStream.listen((state) {
      if (_exhausted && !isPaid() && isFreeUser()) {
        _ensureStopped();
        return;
      }
      if (_isPlayingAudibly()) {
        _ensureStarted();
      } else {
        _ensureStopped();
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _playingSub?.cancel();
    _procSub?.cancel();
    _exhaustedCtr.close();
  }

  void start() {
    if (_active) return;
    _ensureStarted();
  }

  void stop() {
    _ensureStopped();
  }

  /// Сбрасывает флаг «исчерпано», чтобы тикер снова мог стартовать.
  void resetExhaustion() {
    if (_exhausted) {
      _exhausted = false;
      // Если прямо сейчас идёт воспроизведение — запустим тикер.
      if (_isPlayingAudibly() && !isPaid() && isFreeUser()) {
        _ensureStarted();
      }
    }
  }

  bool get isExhausted => _exhausted;

  // --- внутреннее ---

  void _ensureStarted() {
    if (_active) return;
    if (isPaid()) return;
    if (!isFreeUser()) return;     // в ad-mode не считаем секунды
    if (_exhausted) {
      return;
    }
    if (!_isPlayingAudibly()) return;

    _active = true;
    _lastPosition = player.position;
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  void _ensureStopped() {
    // Даже если тикер не стартовал (_active == false), попробуем дослать расход,
    // чтобы короткие сессии не терялись.
    final wasActive = _active;
    unawaited(_consumePendingIfAny(reason: wasActive ? 'stop' : 'stop-inactive'));

    if (!wasActive) return;

    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _forcePauseEverywhere() async {
    try {
      await player.pause();
    } catch (_) {}
  }

  Future<void> _tick() async {
    try {
      if (!_active) return;
      if (isPaid()) { _ensureStopped(); return; }
      if (!isFreeUser()) { _ensureStopped(); return; }
      if (_exhausted) { _ensureStopped(); return; }
      if (!_isPlayingAudibly()) { _ensureStopped(); return; }

      final current = player.position;
      var delta = current - _lastPosition;
      _lastPosition = current;

      if (delta.isNegative || delta > tickInterval * 2) {
        delta = tickInterval;
      }
      final seconds = delta.inSeconds;
      if (seconds <= 0) return;

      await _postConsume(seconds, reason: 'tick');
    } catch (e, st) {
    }
  }

  bool _isPlayingAudibly() {
    if (!player.playing) return false;
    final proc = player.processingState;
    if (proc == ProcessingState.idle ||
        proc == ProcessingState.loading ||
        proc == ProcessingState.buffering) {
      return false;
    }
    return true;
  }

  Future<void> _enforceExhaustionAndSyncZero() async {
    _exhausted = true;

    // Немедленно останавливаем тикер и ставим на паузу, чтобы звук не шёл поверх пейволла.
    _ensureStopped();
    if (!isPaid() && isFreeUser()) {
      await _forcePauseEverywhere();
    }

    try {
      await dio.post(
        '/api/credits/consume',
        data: {'seconds': 0, 'context': 'player'},
        options: Options(headers: {'Accept': 'application/json'}),
      );
    } catch (e) {
    }

    _exhaustedCtr.add(null);
    onExhausted?.call();
  }

  Future<void> _consumePendingIfAny({String reason = 'stop'}) async {
    if (isPaid()) return;
    if (!isFreeUser()) return;

    final current = player.position;
    var delta = current - _lastPosition;
    if (delta.isNegative) {
      return;
    }
    if (delta > tickInterval * 2) {
      delta = tickInterval;
    }

    final seconds = delta.inSeconds;
    if (seconds <= 0) {
      return;
    }

    _lastPosition = current;
    await _postConsume(seconds, reason: reason);
  }

  Future<void> _postConsume(int seconds, {required String reason}) async {
    try {
      final resp = await dio.post(
        '/api/credits/consume',
        data: {'seconds': seconds, 'context': 'player'},
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (resp.statusCode == 200 && resp.data is Map && resp.data['ok'] == true) {
        final remainSec = (resp.data['remaining_seconds'] ?? 0) as int;
        final remainMin = (resp.data['remaining_minutes'] ?? 0) as int;

        // ⬇️ если баланс снова > 0 — снимаем блокировку исчерпания
        if (remainSec > 0 && _exhausted) {
          _exhausted = false;
        }

        onBalanceUpdated?.call(remainSec, remainMin);

        if (remainSec <= 0) {
          await _enforceExhaustionAndSyncZero();
        }
      }
    } catch (e, st) {
    }
  }
}
