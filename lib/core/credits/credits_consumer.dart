// lib/core/credits/credits_consumer.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Потребитель «секунд без рекламы» для free-пользователей.
/// Сам подписывается на состояние плеера и включает тикер,
/// независимо от того, откуда нажали Play (деталка/центральная кнопка/виджет).
class CreditsConsumer {
  final Dio dio;
  final AudioPlayer player;
  final bool Function() isPaid;        // true -> списывать не нужно
  final bool Function() isFreeUser;    // true -> free
  final void Function(int secondsLeft, int minutesLeft)? onBalanceUpdated;
  final VoidCallback? onExhausted;

  /// Как часто отправляем на бэк.
  final Duration tickInterval;

  Timer? _timer;
  Duration _lastPosition = Duration.zero;
  bool _active = false; // активен ли тикер (мы его запустили)
  bool _exhausted = false; // баланс исчерпан: жёстко блокируем проигрывание
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _procSub;

  // Глобальная нотификация об исчерпании (для любых экранов/виджетов)
  final _exhaustedCtr = StreamController<void>.broadcast();
  Stream<void> get exhausted => _exhaustedCtr.stream;

  CreditsConsumer({
    required this.dio,
    required this.player,
    required this.isPaid,
    required this.isFreeUser,
    this.onBalanceUpdated,
    this.onExhausted,
    this.tickInterval = const Duration(seconds: 20),
  }) {
    // Сразу подписываемся на состояния плеера — это покрывает центральную кнопку/виджет/и т.д.
    _playingSub = player.playingStream.listen((playing) async {
      if (kDebugMode) debugPrint('[CreditsConsumer] playing=$playing');
      // Если кто-то попытался проигрывать при исчерпанном балансе — тут же стопаем.
      if (playing && _exhausted && !isPaid()) {
        if (kDebugMode) debugPrint('[CreditsConsumer] BLOCK play (exhausted) -> pause()');
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
      if (kDebugMode) debugPrint('[CreditsConsumer] processing=$state');
      if (_exhausted && !isPaid()) {
        // На всякий случай дублируем блокировку при любых изменениях процесса проигрывания
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

  /// Явный старт: теперь учитывает флаг исчерпания.
  void start() => _ensureStarted();

  /// Явный стоп (на паузе/логауте и т.п.)
  void stop() => _ensureStopped();

  /// Сбрасываем состояние исчерпания, например, после покупки/пополнения,
  /// чтобы снова разрешить проигрывание и тикер.
  void resetExhaustion() {
    if (kDebugMode) debugPrint('[CreditsConsumer] resetExhaustion()');
    _exhausted = false;
  }

  void dispose() {
    _ensureStopped();
    _playingSub?.cancel();
    _procSub?.cancel();
    _exhaustedCtr.close();
  }

  // --- внутреннее ---

  void _ensureStarted() {
    if (_active) return;
    if (isPaid()) return;
    if (!isFreeUser()) return;
    if (_exhausted) {
      if (kDebugMode) debugPrint('[CreditsConsumer] not starting (exhausted)');
      return;
    }
    if (!_isPlayingAudibly()) return;

    _active = true;
    _lastPosition = player.position; // чтобы не поймать большую дельту при резюме

    _timer = Timer.periodic(tickInterval, (_) => _tick());
    if (kDebugMode) debugPrint('[CreditsConsumer] TICKER START');
  }

  void _ensureStopped() {
    if (!_active) return;
    _active = false;
    _timer?.cancel();
    _timer = null;
    if (kDebugMode) debugPrint('[CreditsConsumer] TICKER STOP');
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

      var seconds = delta.inSeconds;
      if (seconds <= 0) return;
      if (seconds > 300) seconds = 300; // защита от скачков

      if (kDebugMode) debugPrint('[CreditsConsumer] POST consume seconds=$seconds');

      final resp = await dio.post(
        '/api/credits/consume',
        data: {'seconds': seconds, 'context': 'player'},
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (resp.statusCode == 200 && resp.data is Map && resp.data['ok'] == true) {
        final remainSec = (resp.data['remaining_seconds'] ?? 0) as int;
        final remainMin = (resp.data['remaining_minutes'] ?? 0) as int;

        onBalanceUpdated?.call(remainSec, remainMin);

        if (remainSec <= 0) {
          await _enforceExhaustionAndSyncZero();
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[CreditsConsumer] consume error: $e');
        debugPrint('$st');
      }
      // Сеть/бэк отвалились — попробуем на следующем тике.
    }
  }

  bool _isPlayingAudibly() {
    // Списываем только когда действительно идёт воспроизведение.
    if (!player.playing) return false;
    final proc = player.processingState;
    if (proc == ProcessingState.idle ||
        proc == ProcessingState.loading ||
        proc == ProcessingState.buffering) {
      return false;
    }
    return true;
  }

  // Принудительно останавливаем проигрывание везде.
  Future<void> _forcePauseEverywhere() async {
    try {
      await player.pause();
    } catch (_) {}
    _ensureStopped();
  }

  // Единая точка: отмечаем исчерпание, паузим плеер, шлём seconds=0, нотифицируем UI.
  Future<void> _enforceExhaustionAndSyncZero() async {
    if (_exhausted) return; // уже обработано
    _exhausted = true;

    if (kDebugMode) debugPrint('[CreditsConsumer] EXHAUSTED -> pause & zero-sync');

    // 1) Останавливаем тикер и плеер.
    await _forcePauseEverywhere();

    // 2) Одноразовая нулевая синхронизация.
    try {
      if (kDebugMode) debugPrint('[CreditsConsumer] POST consume seconds=0');
      await dio.post(
        '/api/credits/consume',
        data: {'seconds': 0, 'context': 'player'},
        options: Options(headers: {'Accept': 'application/json'}),
      );
      if (kDebugMode) debugPrint('[CreditsConsumer] zero-sync sent after exhaust');
    } catch (e) {
      if (kDebugMode) debugPrint('[CreditsConsumer] zero-sync error: $e');
    }

    // 3) Дадим знать всем экранам (paywall/баннер/диалог).
    _exhaustedCtr.add(null);
    onExhausted?.call();
  }
}
