// lib/providers/audio_player_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/constants.dart';
import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/user.dart'; // enum UserType, getUserType
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

import 'package:booka_app/repositories/profile_repository.dart';
import 'package:booka_app/core/credits/credits_consumer.dart'; // списание секунд

// ---- КЛЮЧИ ДЛЯ PREFS ----
const String _kCurrentListenKey = 'current_listen';
const String _kProgressMapKey = 'listen_progress_v1';
const String _kChaptersCachePrefix = 'chapters_cache_v1_';

// ==== помощники времени (UTC)
DateTime _nowUtc() => DateTime.now().toUtc();
DateTime? _parseUtc(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString()).toUtc();
  } catch (_) {
    return null;
  }
}

bool _isAfterWithSkew(DateTime a, DateTime b, {int skewSec = 3}) =>
    a.isAfter(b.add(Duration(seconds: skewSec)));

Future<void> saveCurrentListenToPrefs({
  required Book? book,
  required Chapter? chapter,
  required int position,
  DateTime? updatedAt,
}) async {
  final prefs = await SharedPreferences.getInstance();

  if (book == null || chapter == null) {
    await prefs.remove(_kCurrentListenKey);
    if (kDebugMode) debugPrint('saveCurrentListen: CLEARED');
    return;
  }

  final payload = <String, dynamic>{
    'book': book.toJson(),
    'chapter': chapter.toJson(),
    'position': position,
    'book_id': book.id,
    'chapter_id': chapter.id,
    'updated_at': (updatedAt ?? _nowUtc()).toIso8601String(),
  };

  await prefs.setString(_kCurrentListenKey, json.encode(payload));
}

// ---------- ЛОКАЛЬНАЯ ЗАГРУЗКА CL ----------
class _LocalCL {
  final int? bookId;
  final int? chapterId;
  final int position;
  final DateTime? updatedAt;
  final Map<String, dynamic>? bookJson;
  final Map<String, dynamic>? chapterJson;

  _LocalCL({
    required this.bookId,
    required this.chapterId,
    required this.position,
    required this.updatedAt,
    required this.bookJson,
    required this.chapterJson,
  });
}

class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();

  // ====== Интеграция списания секунд (CreditsConsumer)
  CreditsConsumer? _creditsConsumer;
  CreditsConsumer? get creditsConsumer => _creditsConsumer;

  int Function()? getFreeSeconds;
  void Function(int)? setFreeSeconds;

  VoidCallback? onCreditsExhausted;

  // === AD-MODE ===
  Future<bool> Function()? onNeedAdConsent;
  Future<void> Function()? onShowIntervalAd;

  bool _adMode = false;
  bool _adConsentShown = false;

  // 🔥 1. ДОБАВЛЕНО: Статус загрузки рекламы (для UI, если нужно)
  bool _isAdLoading = false;
  bool get isAdLoading => _isAdLoading;

  // 🔥 Поле, которое терялось ранее
  DateTime? _lastAdAt;

  // 🔥 НОВАЯ ЛОГИКА ТАЙМЕРА (Секундомер)
  static const Duration _adInterval = Duration(minutes: 1);

  // Скільки часу залишилось до реклами (зберігається при паузі)
  Duration _remainingAdDuration = _adInterval;

  // Час, коли спрацює реклама (якщо грає). Null, якщо пауза.
  DateTime? _adTargetTime;

  Timer? _adTimer;

  bool _pendingAdDueToBackground = false;

  int _adScheduleSuspend = 0;
  bool get isAdScheduleSuspended => _adScheduleSuspend > 0;

  bool get isAdMode => _adMode;

  // 🔥 Геттер для UI: повертає реальний час до реклами
  Duration get timeUntilNextAd {
    if (!_adMode) return Duration.zero;

    // Якщо плеєр грає — рахуємо різницю від "прицільного" часу
    if (_adTargetTime != null) {
      final left = _adTargetTime!.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }

    // Якщо пауза — повертаємо "заморожений" залишок
    return _remainingAdDuration;
  }

  // Для сумісності
  DateTime? get nextAdTime => _adTargetTime;

  // ====== СЕКУНДНЫЙ ЛОКАЛЬНЫЙ ТИКЕР ДЛЯ UI
  Timer? _freeSecondsTicker;
  static const Duration _uiSecTick = Duration(seconds: 1);

  Timer? _pendingRearmTimer;

  // ====== Скорость/список/индексы/позиции
  double _speed = 1.0;
  List<Chapter> _chapters = [];
  int _currentChapterIndex = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // ===== UI throttle и drag override для слайдера
  bool _isUserSeeking = false;
  Duration? _uiPositionOverride;
  Duration get uiPosition => _uiPositionOverride ?? _position;

  DateTime _lastUiTick = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _uiTick = Duration(milliseconds: 200);

  // троттлинг сохранения прогресса (локально)
  DateTime? _lastPersistAt;
  final Duration _persistEvery = const Duration(seconds: 10);

  bool _isPreparing = false;
  bool _hydrating = false;
  Completer<bool>? _hydrateCompleter;

  Map<String, dynamic>? _progressMapCache;

  // ======= PUSH прогресса на API ======= и дебаунс
  Timer? _serverPushTimer;
  String? _lastPushSig;
  final Duration _pushDelay = const Duration(seconds: 5);
  static const int _minAutoPushSec = 2;

  UserType _userType = UserType.guest;
  UserType get userType => _userType;

  set userType(UserType value) {
    if (_userType == value) return;
    _log('userType := $value');
    _userType = value;

    // переключение статусов выключает/включает списание и ad-mode
    if (_userType != UserType.free) {
      _disableAdMode();
    }
    _reinitCreditsConsumer();
    _rearmFreeSecondsTicker(); // переключим тикер с учётом нового статуса
    notifyListeners();
  }

  void Function()? _onGuestFirstChapterEnd;
  set onGuestFirstChapterEnd(void Function()? cb) => _onGuestFirstChapterEnd = cb;

  bool get isPlaying => player.playing;
  double get speed => _speed;
  Duration get position => _position;
  Duration get duration => _duration;

  Chapter? get currentChapter =>
      _chapters.isNotEmpty ? _chapters[_currentChapterIndex] : null;

  Book? get currentBook =>
      _chapters.isNotEmpty && _chapters[_currentChapterIndex].book != null
          ? Book.fromJson(_chapters[_currentChapterIndex].book!)
          : null;

  List<Chapter> get chapters => _chapters;

  String? get currentUrl => currentChapter?.audioUrl;
  bool get _hasSequence => (player.sequenceState?.sequence.isNotEmpty ?? false);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _pausedByConnectivity = false;
  String? _connectivityMessage;
  String? get connectivityMessage => _connectivityMessage;
  bool get pausedByConnectivity => _pausedByConnectivity;

  AudioPlayerProvider() {
    // Позиция
    player.positionStream.listen((pos) {
      if (!_hasSequence) return;

      if (_position > Duration.zero && pos == Duration.zero) {
        return;
      }

      _position = pos;

      if (pos > _duration) {
        _duration = pos;
      }
      _saveProgressThrottled();
      _scheduleServerPush();

      if (_isUserSeeking) return;

      final now = DateTime.now();
      if (now.difference(_lastUiTick) >= _uiTick) {
        _lastUiTick = now;
        notifyListeners();
      }
    });

    // Сводное состояние плеера
    player.playerStateStream.listen((_) {
      _rearmFreeSecondsTicker();
      _syncAdScheduleWithPlayback();
    });

    // Длительность
    player.durationStream.listen((dur) {
      if (dur == null) return;

      final safeDuration = dur < _position ? _position : dur;
      if (safeDuration != _duration) {
        _duration = safeDuration;
        notifyListeners();
      }
    });

    player.sequenceStateStream.listen((_) => _pullDurationFromPlayer());

    // Переключение раздела
    player.currentIndexStream.listen((idx) {
      if (idx != null && idx >= 0 && idx < _chapters.length) {
        _currentChapterIndex = idx;
        _lastPushSig = null;
        _pullDurationFromPlayer();
        notifyListeners();
      }
    });

    // Скорость
    player.speedStream.listen((s) {
      _speed = s;
      _rearmFreeSecondsTicker();
      notifyListeners();
    });

    // Конец трека/раздела
    player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        _saveProgressThrottled(force: true);
        await _pushProgressToServer(force: true);

        final hasNext = _currentChapterIndex + 1 < _chapters.length;

        if (_userType == UserType.guest) {
          _log('ProcessingState.completed for GUEST — остановка');
          _onGuestFirstChapterEnd?.call();
          await player.stop();
          return;
        }

        if (hasNext) {
          await nextChapter();
        } else {
          await player.seek(Duration.zero);
          await player.pause();
        }
      }

      _rearmFreeSecondsTicker();
      _syncAdScheduleWithPlayback();
    });

    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_handleConnectivityChange);

    Connectivity()
        .checkConnectivity()
        .then(_handleConnectivityChange);
  }

  Future<void> _handleConnectivityChange(
      List<ConnectivityResult> events) async {
    final connected =
        events.isNotEmpty && events.any((event) => event != ConnectivityResult.none);

    if (!connected) {
      // 🔴 ИНТЕРНЕТ ПРОПАЛ
      if (player.playing) {
        _pausedByConnectivity = true;
        pause(fromConnectivity: true);
      }
      _connectivityMessage =
      'Немає з’єднання з інтернетом. Відтворення призупинено.';

      notifyListeners();
    } else {
      // 🟢 ИНТЕРНЕТ ПОЯВИЛСЯ
      _connectivityMessage = null;
      notifyListeners();

      if (_pausedByConnectivity && !player.playing) {
        _pausedByConnectivity = false;
        try {
          await play();
        } catch (e) {
          _log('Auto-resume failed: $e');
        }
      }
    }
  }

  // ======== ЛОКАЛЬНЫЙ СЕКУНДНЫЙ ТИКЕР ДЛЯ БЕЙДЖА МИНУТ/СЕКУНД ========
  void _startFreeSecondsTicker() {
    if (_freeSecondsTicker != null) return;
    _log('freeSecondsTicker: START');
    _freeSecondsTicker = Timer.periodic(_uiSecTick, (_) {
      if (!_isPlayingAudibly() || _userType != UserType.free) return;

      final getFn = getFreeSeconds;
      final setFn = setFreeSeconds;
      if (getFn == null || setFn == null) return;

      final int current = getFn() ?? 0;
      if (current <= 0) return;

      final int next = current - 1;
      setFn(next < 0 ? 0 : next);
    });
  }

  void _stopFreeSecondsTicker() {
    if (_freeSecondsTicker == null) return;
    _log('freeSecondsTicker: STOP');
    _freeSecondsTicker?.cancel();
    _freeSecondsTicker = null;
  }

  // Публичная безопасная обёртка
  void rearmFreeSecondsTickerSafely() {
    _rearmFreeSecondsTicker(retryIfNotReady: true);
  }

  void _rearmFreeSecondsTicker({bool retryIfNotReady = false}) {
    final readyNow = (_userType == UserType.free) && player.playing;
    if (readyNow) {
      _pendingRearmTimer?.cancel();
      _pendingRearmTimer = null;
      _startFreeSecondsTicker();
      return;
    }

    _stopFreeSecondsTicker();

    if (retryIfNotReady) {
      _pendingRearmTimer?.cancel();
      _pendingRearmTimer = Timer(const Duration(milliseconds: 300), () {
        _rearmFreeSecondsTicker(retryIfNotReady: false);
      });
    }
  }

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

  void _log(String msg) {
    if (kDebugMode) debugPrint('[AUDIO] $msg');
  }

  void _pullDurationFromPlayer() {
    final fallback = _chapters.isNotEmpty
        ? Duration(seconds: _chapters[_currentChapterIndex].duration ?? 0)
        : Duration.zero;

    final d = player.duration ?? fallback;
    final safeDuration = d < _position ? _position : d;

    if (safeDuration != _duration) {
      _duration = safeDuration;
      notifyListeners();
    }
  }

  // ---------- ИНИЦИАЛИЗАЦИЯ CreditsConsumer ----------

  void _ensureCreditsConsumer() {
    if (_userType == UserType.paid || _userType == UserType.guest) {
      _creditsConsumer?.stop();
      _creditsConsumer = null;
      return;
    }

    if (_creditsConsumer == null) {
      _creditsConsumer = CreditsConsumer(
        dio: ApiClient.i(),
        player: player,
        isPaid: () => _userType == UserType.paid,
        // ⬇️ в ad-mode не списываем — consumer сам ничего не блокирует
        isFreeUser: () => _userType == UserType.free && !_adMode,
        onBalanceUpdated: (secLeft, minLeft) {
          setFreeSeconds?.call(secLeft < 0 ? 0 : secLeft);
          if (secLeft > 0 && _adMode) {
            _log('balance>0 → disable ad-mode');
            _disableAdMode();
            _syncAdScheduleWithPlayback();
          }
        },
        onExhausted: () async {
          onCreditsExhausted?.call();
        },
        tickInterval: const Duration(seconds: 20),
      );
      if (kDebugMode) _log('CreditsConsumer создан');
    }
  }

  void _reinitCreditsConsumer() {
    _creditsConsumer?.stop();
    _creditsConsumer = null;
    _ensureCreditsConsumer();
    if (player.playing) {
      _creditsConsumer?.start();
    }
  }

  Future<void> ensureCreditsTickerBound() async {
    try {
      if (_userType == UserType.paid || _userType == UserType.guest || _adMode) {
        _creditsConsumer?.stop();
        _rearmFreeSecondsTicker();
        return;
      }
      _ensureCreditsConsumer();
      if (player.playing) {
        _creditsConsumer?.start();
      } else {
        _creditsConsumer?.stop();
      }
      _rearmFreeSecondsTicker();
    } catch (e, st) {
      _log('ensureCreditsTickerBound error: $e\n$st');
    }
  }

  void resetCreditsExhaustion() {
    if (kDebugMode) _log('resetCreditsExhaustion()');
    final consumer = _creditsConsumer;
    consumer?.resetExhaustion();
    if (player.playing) {
      consumer?.start();
    }
    _rearmFreeSecondsTicker();
  }

  void onExternalFreeSecondsUpdated(int seconds) {
    final consumer = _creditsConsumer;

    if (consumer == null) {
      if (seconds <= 0) {
        _stopFreeSecondsTicker();
      }
      return;
    }

    if (seconds <= 0) {
      if (kDebugMode) _log('external free seconds → exhausted ($seconds)');
      consumer.stop();
      _stopFreeSecondsTicker();

      // FIX: Если секунды закончились (например, локальный тикер дошел до 0)
      // и плеер активно играет (и не в ad-mode), то нужно принудительно остановить воспроизведение.
      if (player.playing && _userType == UserType.free && !_adMode) {
        _log('external free seconds hit zero while playing. Forcing pause.');
        player.pause();
      }

      return;
    }

    if (consumer.isExhausted) {
      if (kDebugMode) {
        _log('external free seconds → reset exhaustion ($seconds)');
      }
      consumer.resetExhaustion();
    }

    if (player.playing) {
      consumer.start();
    }

    _rearmFreeSecondsTicker();
  }

  // ---------- ХРАНИЛИЩЕ ПРОГРЕССА ПО КНИГАМ ----------
  Future<Map<String, dynamic>> _readProgressMap() async {
    if (_progressMapCache != null) return _progressMapCache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProgressMapKey);
    if (raw == null || raw.isEmpty) {
      _progressMapCache = <String, dynamic>{};
      return _progressMapCache!;
    }
    try {
      final map = json.decode(raw);
      _progressMapCache =
      (map is Map<String, dynamic>) ? map : <String, dynamic>{};
    } catch (_) {
      _progressMapCache = <String, dynamic>{};
    }
    return _progressMapCache!;
  }

  Future<void> _writeProgressMap(Map<String, dynamic> map) async {
    _progressMapCache = map;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProgressMapKey, json.encode(map));
    } catch (_) {}
  }

  Future<void> _writeProgressEntry({
    required int bookId,
    required int chapterId,
    required int positionSec,
  }) async {
    final map = await _readProgressMap();

    map['$bookId'] = {
      'chapterId': chapterId,
      'position': positionSec,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    if (map.length > 50) {
      final entries = map.entries.toList();
      entries.sort((a, b) {
        final av = (a.value is Map && a.value['updatedAt'] is int)
            ? a.value['updatedAt'] as int
            : 0;
        final bv = (b.value is Map && b.value['updatedAt'] is int)
            ? b.value['updatedAt'] as int
            : 0;
        return av.compareTo(bv);
      });
      final toRemove = entries.take(entries.length - 50);
      for (final e in toRemove) {
        map.remove(e.key);
      }
    }

    await _writeProgressMap(map);
  }

  Future<Map<String, dynamic>?> _getProgressForBook(int bookId) async {
    final map = await _readProgressMap();
    final v = map['$bookId'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  Future<int?> getSavedChapterIndex(int bookId, List<Chapter> chapters) async {
    final saved = await _getProgressForBook(bookId);
    if (saved == null) return null;

    final savedChapterId = saved['chapterId'];
    if (savedChapterId is int) {
      final idx = chapters.indexWhere((c) => c.id == savedChapterId);
      if (idx != -1) return idx;
    }

    return null;
  }

  Future<_LocalCL?> _loadLocalCL() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kCurrentListenKey);
    if (s == null) return null;
    try {
      final m = json.decode(s) as Map<String, dynamic>;
      final bookJson =
      (m['book'] is Map) ? Map<String, dynamic>.from(m['book']) : null;
      final chapterJson =
      (m['chapter'] is Map) ? Map<String, dynamic>.from(m['chapter']) : null;

      int? bookId;
      int? chapterId;
      if (m['book_id'] is int) {
        bookId = m['book_id'] as int;
      } else if (m['book_id'] != null) {
        bookId = int.tryParse('${m['book_id']}');
      }
      if (m['chapter_id'] is int) {
        chapterId = m['chapter_id'] as int;
      } else if (m['chapter_id'] != null) {
        chapterId = int.tryParse('${m['chapter_id']}');
      }

      bookId ??= (bookJson?['id'] is int)
          ? bookJson!['id'] as int
          : int.tryParse('${bookJson?['id']}');
      chapterId ??=
      (chapterJson?['id'] is int)
          ? chapterJson!['id'] as int
          : int.tryParse('${chapterJson?['id']}');

      final pos = (m['position'] is int)
          ? m['position'] as int
          : int.tryParse('${m['position']}') ?? 0;

      final upd = _parseUtc(m['updated_at']);

      return _LocalCL(
        bookId: bookId,
        chapterId: chapterId,
        position: pos,
        updatedAt: upd,
        bookJson: bookJson,
        chapterJson: chapterJson,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------- СОХРАНЕНИЕ ПРОГРЕССА (локально) ----------
  void _saveProgressThrottled({bool force = false}) {
    final b = currentBook;
    final ch = currentChapter;
    if (b == null || ch == null) return;

    final posSec = _position.inSeconds;
    if (posSec <= 0) return;

    final now = DateTime.now();
    if (!force) {
      final last = _lastPersistAt;
      if (last != null && now.difference(last) < _persistEvery) return;
    }
    _lastPersistAt = now;

    saveCurrentListenToPrefs(
      book: b,
      chapter: ch,
      position: posSec,
      updatedAt: _nowUtc(),
    );

    _writeProgressEntry(
      bookId: b.id,
      chapterId: ch.id,
      positionSec: posSec,
    );
  }

  // ---------- PUSH ПРОГРЕССА НА СЕРВЕР ----------
  void _scheduleServerPush() {
    if (_userType == UserType.guest) return;
    if (currentBook == null || currentChapter == null) return;
    if (!player.playing) return;
    if (_position.inSeconds < _minAutoPushSec) return;

    _serverPushTimer?.cancel();
    _serverPushTimer = Timer(_pushDelay, () => _pushProgressToServer());
  }

  String _buildPushSig(int bookId, int chapterId, int posSec) =>
      '$bookId:$chapterId:$posSec';

  Future<void> _pushProgressToServer({
    bool force = false,
    bool allowZero = false,
  }) async {
    final b = currentBook;
    final ch = currentChapter;
    if (b == null || ch == null) return;
    if (_userType == UserType.guest) return;

    final pos = _position.inSeconds;

    if (!allowZero && pos == 0) return;

    if (!force) {
      if (!player.playing) return;
      if (pos < _minAutoPushSec) return;
    }

    final sig = _buildPushSig(b.id, ch.id, pos);
    if (!force && _lastPushSig == sig) return;

    try {
      final resp = await ApiClient.i().post(
        '/listens',
        data: {'a_book_id': b.id, 'a_chapter_id': ch.id, 'position': pos},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (resp.statusCode == 404) {
        await ApiClient.i().post(
          '/listen/update',
          data: {'a_book_id': b.id, 'a_chapter_id': ch.id, 'position': pos},
          options: Options(validateStatus: (s) => s != null && s < 500),
        );
      }
      _lastPushSig = sig;
      _log('pushProgress: OK pos=$pos (book=${b.id}, ch=${ch.id})');
    } catch (e) {
      _log('pushProgress: error: $e');
    }
  }

  // ---------- HELPERS: свежий Bearer для аудио ----------
  Map<String, String>? _authHeaders() {
    final access = AuthStore.I.accessToken;
    if (access != null && access.isNotEmpty) {
      return {'Authorization': 'Bearer $access'};
    }
    return null;
  }

  String? _normalizeAudioUrl(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;

    if (s.startsWith('http')) {
      return s.replaceFirst('http://', 'https://');
    }

    final path = s.startsWith('storage/')
        ? s
        : (s.startsWith('/storage/') ? s.substring(1) : 'storage/$s');

    return fullResourceUrl(path);
  }

  String? _absImageUrl(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    if (s.startsWith('http')) return s.replaceFirst('http://', 'https://');
    final p = s.startsWith('/') ? s.substring(1) : s;
    return fullResourceUrl(p);
  }

  String? _authorFromBook(Map<String, dynamic>? bookMap) {
    if (bookMap == null) return null;
    final v = bookMap['author'] ?? bookMap['authors'];
    if (v is Map && v['name'] != null) {
      final s = v['name'].toString().trim();
      return s.isNotEmpty ? s : null;
    }
    if (v is String) {
      final s = v.trim();
      return s.isNotEmpty ? s : null;
    }
    return null;
  }

  String? _titleFromBook(Map<String, dynamic>? bookMap) {
    if (bookMap == null) return null;
    final s = (bookMap['title'] ?? bookMap['name'] ?? '').toString().trim();
    return s.isNotEmpty ? s : null;
  }

  String? _coverFromBook(Map<String, dynamic>? bookMap) {
    if (bookMap == null) return null;
    final cand = [
      bookMap['cover_url'],
      bookMap['thumbnailUrl'],
      bookMap['thumb'],
      bookMap['cover'],
      bookMap['image'],
    ];
    for (final c in cand) {
      final u = _absImageUrl(c?.toString());
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }

  // ---------- HELPERS: API access / Chapters fetching (FIX: Добавлен _retrieveAllChaptersForBook) ----------

  // Новый вспомогательный метод для получения полного списка глав для книги.
  Future<List<Chapter>> _retrieveAllChaptersForBook(int bookId) async {
    try {
      final resp = await ApiClient.i().get(
        '/abooks/$bookId/chapters',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (resp.statusCode != 200) return [];

      final raw = resp.data;
      final List<dynamic> items = (raw is List)
          ? raw
          : (raw is Map<String, dynamic>)
          ? (raw['data'] ?? raw['items'] ?? [])
          : [];

      final list = items.map((it) => Chapter.fromJson(
        Map<String, dynamic>.from(it as Map),
        book: {'id': bookId},
      )).toList();

      // 🔥 ДОБАВЛЕНО: Сохраняем в кэш для следующего раза
      if (list.isNotEmpty) {
        _cacheChaptersForBook(bookId, list);
      }

      return list;
    } catch (e) {
      _log('retrieveAllChaptersForBook error: $e');
      return [];
    }
  }

  Future<Chapter?> _fetchChapterById(int bookId, int chapterId) async {
    final chapters = await _retrieveAllChaptersForBook(bookId);

    for (final ch in chapters) {
      if (ch.id == chapterId) return ch;
    }
    return null;
  }

  // ------------------------------------------------------------------------------------------------------

  AudioSource _sourceForChapter(
      Chapter chapter, {
        String? prettyTitle,
        String? artist,
        String? coverUrl,
        String? bookTitle,
      }) {
    final title = (prettyTitle != null && prettyTitle.isNotEmpty)
        ? prettyTitle
        : (chapter.title.isNotEmpty ? chapter.title : 'Розділ');

    final normalizedUrl = _normalizeAudioUrl(chapter.audioUrl);
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      throw StateError('Chapter ${chapter.id} has no valid audioUrl');
    }

    final albumName = ((bookTitle ?? '').trim()).isNotEmpty
        ? bookTitle!.trim()
        : (_titleFromBook(chapter.book) ?? 'Аудіокнига');

    final artistName = (() {
      final s = (artist ?? '').trim();
      if (s.isNotEmpty) return s;
      return _authorFromBook(chapter.book) ?? 'Booka';
    })();

    final artUrl = (() {
      final c1 = _absImageUrl(coverUrl);
      if (c1 != null && c1.isNotEmpty) return c1;
      return _coverFromBook(chapter.book);
    })();

    final displayTitle = title.isNotEmpty ? title : albumName;
    final displaySubtitle = (() {
      if (artistName != null && artistName.isNotEmpty) return artistName;
      return albumName;
    })();

    final description = (() {
      final base = chapter.title.trim();
      final order = chapter.order ?? 0;
      if (order > 0 && base.isNotEmpty) {
        return 'Глава $order: $base';
      }
      if (order > 0) return 'Глава $order';
      return base;
    })();

    final bookIdRaw = chapter.book?['id'] ?? chapter.book?['book_id'];
    final bookId = bookIdRaw is int
        ? bookIdRaw
        : int.tryParse(bookIdRaw?.toString() ?? '');
    final mediaId = bookId != null
        ? 'book:${bookId}_chapter:${chapter.id}'
        : 'chapter:${chapter.id}';

    return AudioSource.uri(
      Uri.parse(normalizedUrl),
      headers: _authHeaders(),
      tag: MediaItem(
        id: mediaId,
        title: title,
        album: albumName,
        artist: artistName,
        artUri: artUrl != null ? Uri.parse(artUrl) : null,
        displayDescription: description.isNotEmpty ? description : null,
        displayTitle: displayTitle,
        displaySubtitle: displaySubtitle,
        extras: {
          'bookTitle': albumName,
          if (artistName != null) 'artistName': artistName,
          if (bookId != null) 'bookId': bookId,
          'chapterId': chapter.id,
          'chapterOrder': chapter.order,
          'chapterTitle': chapter.title,
          if (artUrl != null) 'artUrl': artUrl,
        },
        duration: (chapter.duration != null && chapter.duration! > 0)
            ? Duration(seconds: chapter.duration!)
            : null,
      ),
    );
  }

  ConcatenatingAudioSource _playlistFromChapters({
    required List<Chapter> list,
    String? bookTitle,
    String? artist,
    String? coverUrl,
  }) {
    final children = list.map((ch) {
      final prettyTitle = (bookTitle != null && bookTitle.isNotEmpty)
          ? '$bookTitle — ${ch.title}'
          : ch.title;
      return _sourceForChapter(
        ch,
        prettyTitle: prettyTitle,
        artist: artist,
        coverUrl: coverUrl,
        bookTitle: bookTitle,
      );
    }).toList();

    return ConcatenatingAudioSource(
      useLazyPreparation: false,
      children: children,
    );
  }

  // ---------- ПУБЛИЧНЫЕ ОБЁРТКИ ----------
  Future<bool> hydrateFromServerIfAvailable() => _hydrateFromServerIfAvailable();

  Future<void> ensurePrepared() async {
    await _prepareFromSavedIfNeeded();
  }

  Future<void> seekTo(Duration position) => seek(position);

  Future<void> changeSpeed() async {
    const steps = <double>[0.8, 1.0, 1.25, 1.5, 1.75, 2.0];
    final idx = steps.indexWhere((v) => (v - _speed).abs() < 0.001);
    final next = idx == -1 ? 1.0 : steps[(idx + 1) % steps.length];
    await setSpeed(next);
  }

  Future<bool> hasSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kCurrentListenKey);
  }

  Future<void> flushProgress() async {
    _saveProgressThrottled(force: true);
    await _pushProgressToServer(force: true, allowZero: false);
  }

  Map<String, dynamic>? _normalizeProfile(dynamic raw) {
    if (raw == null) return null;

    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      final out = <String, dynamic>{};
      (raw as Map).forEach((k, v) => out['$k'] = v);
      return out;
    }
    if (raw is User) {
      try {
        final dyn = raw as dynamic;
        final maybe = dyn.toJson?.call();
        if (maybe is Map) {
          final out = <String, dynamic>{};
          (maybe as Map).forEach((k, v) => out['$k'] = v);
          return out;
        }
      } catch (_) {}
      final out = <String, dynamic>{
        'name': raw.name,
        'email': raw.email,
        'is_paid': ((raw as dynamic).isPaid ?? (raw as dynamic).is_paid) == true,
      };
      try {
        final dyn = raw as dynamic;
        if (dyn.current_listen != null) out['current_listen'] = dyn.current_listen;
        if (dyn.currentListen != null) out['current_listen'] = dyn.currentListen;
        if (dyn.server_time != null) out['server_time'] = dyn.server_time;
      } catch (_) {}
      return out;
    }
    return null;
  }

  Future<bool> _hydrateFromServerIfAvailable() async {
    if (!AuthStore.I.isLoggedIn) {
      _log('hydrate: not logged in → skip');
      return false;
    }

    final local = await _loadLocalCL();
    if (local != null) {
      _log('hydrate: локальная сессия существует → пропускаем сеть');
      return false;
    }

    if (_hydrating) {
      return _hydrateCompleter!.future;
    }
    _hydrating = true;
    _hydrateCompleter = Completer<bool>();

    try {
      final profRaw = await ProfileRepository.I.loadMap(
        force: true,
        debugTag: 'AudioPlayer.hydrate',
      );
      final data = _normalizeProfile(profRaw);
      if (data == null) {
        _log('hydrate: profile is null');
        _hydrateCompleter!.complete(false);
        return false;
      }

      final srv = (data['current_listen'] ??
          data['currentListen'] ??
          data['currentListening']) as Map?;
      if (srv == null) {
        _log('hydrate: в профиле нет current_listен');
        _hydrateCompleter!.complete(false);
        return false;
      }

      final serverNow = _parseUtc(data['server_time']) ?? _nowUtc();

      Future<bool> _applyServerCL(Map<String, dynamic> clMap) async {
        final bookMap =
        (clMap['book'] is Map) ? Map<String, dynamic>.from(clMap['book']) : null;
        final chapterMap = (clMap['chapter'] is Map)
            ? Map<String, dynamic>.from(clMap['chapter'])
            : null;

        final int bookId = (clMap['book_id'] is int)
            ? clMap['book_id'] as int
            : int.tryParse('${clMap['book_id']}') ??
            (bookMap?['id'] as int? ?? 0);
        final int chapterId = (clMap['chapter_id'] is int)
            ? clMap['chapter_id'] as int
            : int.tryParse('${clMap['chapter_id']}') ??
            (chapterMap?['id'] as int? ?? 0);

        final pRaw = clMap['position'] ??
            clMap['current_position'] ??
            clMap['last_position'] ??
            0;
        final int pos = (pRaw is int) ? pRaw : int.tryParse(pRaw.toString()) ?? 0;

        final DateTime upd = _parseUtc(clMap['updated_at']) ?? serverNow;

        Book? book;
        Chapter? chapter;
        if (bookMap != null) book = Book.fromJson(bookMap);
        if (chapterMap != null) {
          chapter = Chapter.fromJson(
            chapterMap,
            book: bookMap ?? {'id': bookId},
          );
        }

        bool _bad(String? s) {
          final v = (s ?? '').trim();
          if (v.isEmpty) return true;
          if (v == ':') return true;
          return false;
        }

        if (chapter == null || _bad(chapter.audioUrl)) {
          final fetched = await _fetchChapterById(bookId, chapterId);
          if (fetched != null) {
            chapter = fetched;
            if (book == null) {
              if (fetched.book != null) {
                book = Book.fromJson(fetched.book!);
              } else {
                book = Book.fromJson({'id': bookId, 'title': '', 'author': ''});
              }
            }
          }
        }

        if (book == null || chapter == null) {
          _log('hydrate: applyServerCL missing book/chapter json — skip');
          return false;
        }

        final normalized = Chapter(
          id: chapter.id,
          title: chapter.title,
          order: chapter.order,
          audioUrl: _normalizeAudioUrl(chapter.audioUrl) ?? '',
          duration: chapter.duration,
          book: chapter.book ?? book.toJson(),
        );

        await saveCurrentListenToPrefs(
          book: book,
          chapter: normalized,
          position: pos,
          updatedAt: upd,
        );
        await _writeProgressEntry(
          bookId: bookId,
          chapterId: normalized.id,
          positionSec: pos,
        );

        _chapters = [normalized];
        _currentChapterIndex = 0;
        _position = Duration(seconds: pos);
        _duration = Duration(seconds: normalized.duration ?? 0);

        _log(
            'hydrate: applied server (book=$bookId, ch=${normalized.id}, pos=$pos, upd=$upd)');
        notifyListeners();
        return true;
      }

      final ok = await _applyServerCL(Map<String, dynamic>.from(srv));
      _hydrateCompleter!.complete(ok);
      return ok;
    } catch (e) {
      _log('hydrate: error: $e');
      _hydrateCompleter!.complete(false);
      return false;
    } finally {
      _hydrating = false;
    }
  }

  // ---------- НАБОР РАЗДЕЛОВ / ПЛЕЙЛИСТ ----------
  Future<void> setChapters(
      List<Chapter> chapters, {
        int startIndex = 0,
        String? bookTitle,
        String? artist,
        String? coverUrl,
        Book? book,
        UserType? userTypeOverride,
        bool ignoreSavedPosition = false,
        // 🔥 1. НОВЫЙ ПАРАМЕТР: точная позиция старта
        Duration? initialPositionOverride,
      }) async {
    final effectiveType = userTypeOverride ?? _userType;
    List<Chapter> playlistChapters = chapters;

    if (effectiveType == UserType.guest) {
      if (chapters.isEmpty) {
        _log('setChapters: guest — пустой список разделов');
        _resetState();
        return;
      }
      Chapter first = chapters.first;
      int best = _orderKey(first);
      for (final c in chapters) {
        final v = _orderKey(c);
        if (v < best) {
          best = v;
          first = c;
        }
      }
      playlistChapters = [first];
    }

    final samePlaylist = _chapters.length == playlistChapters.length &&
        _chapters.asMap().entries.every((e) => e.value.id == playlistChapters[e.key].id);

    if (samePlaylist && _hasSequence) {
      _log('setChapters: same playlist — skip setAudioSource()');
      return;
    }

    int initialIndex = (effectiveType == UserType.guest) ? 0 : startIndex;

    // 🔥 2. ЛОГИКА ОПРЕДЕЛЕНИЯ ПОЗИЦИИ
    Duration initialPos = initialPositionOverride ?? Duration.zero;

    // Если override не передан, используем старую логику проверки истории
    if (initialPositionOverride == null) {
      if (book != null && !ignoreSavedPosition) {
        final saved = await _getProgressForBook(book.id);
        if (saved != null) {
          final savedChapterId = saved['chapterId'];
          final savedPosSec = saved['position'] ?? 0;
          if (savedChapterId is int) {
            final idx = playlistChapters.indexWhere((c) => c.id == savedChapterId);
            if (idx >= 0) {
              initialIndex = idx;
              initialPos = Duration(seconds: savedPosSec is int ? savedPosSec : 0);
            }
          }
        }
      } else {
        // Фоллбэк для плейлиста из 1 элемента
        if (_position > Duration.zero && playlistChapters.length == 1) {
          initialPos = _position;
        }
      }
    }

    _chapters = playlistChapters
        .map((ch) => Chapter(
      id: ch.id,
      title: ch.title,
      order: ch.order,
      audioUrl: _normalizeAudioUrl(ch.audioUrl) ?? '',
      duration: ch.duration,
      book: book != null ? book.toJson() : ch.book,
    ))
        .toList();

    _currentChapterIndex = initialIndex;
    _lastPushSig = null;

    _position = initialPos;
    final fallbackDurSec = _chapters[_currentChapterIndex].duration ?? 0;
    _duration = Duration(seconds: fallbackDurSec);
    notifyListeners();

    final playlist = _playlistFromChapters(
      list: _chapters,
      bookTitle: bookTitle,
      artist: artist,
      coverUrl: coverUrl,
    );

    _log(
        'setChapters: ${_chapters.length} items, start=$_currentChapterIndex, initialPos=${initialPos.inSeconds}s, ignoreSaved=$ignoreSavedPosition');
    try {
      // 🔥 3. АТОМАРНАЯ ИНИЦИАЛИЗАЦИЯ
      await player.setAudioSource(
        playlist,
        initialIndex: _currentChapterIndex,
        initialPosition: initialPos,
      );

      await player.setShuffleModeEnabled(false);
      await player.setLoopMode(LoopMode.off);
    } catch (e) {
      _log('setChapters: setAudioSource error: $e');
      rethrow;
    }

    _pullDurationFromPlayer();
    _rearmFreeSecondsTicker();
    notifyListeners();
  }

  int _orderKey(Chapter c) {
    final o = c.order;
    if (o == null) return 1 << 30;
    return o;
  }

  void _resetState() {
    _chapters = [];
    _currentChapterIndex = 0;
    _position = Duration.zero;
    _duration = Duration.zero;
    _serverPushTimer?.cancel();
    _stopFreeSecondsTicker();
    notifyListeners();
  }

  // ---------- КОНТРОЛЛЕРЫ ВОСПРОИЗВЕДЕНИЯ ----------

  Future<void> play() async {
    _ensureCreditsConsumer();

    if (_userType == UserType.free) {
      final secondsLeft = getFreeSeconds?.call() ?? 0;

      // Если секунды закончились и ad-mode ещё не включён — спрашиваем согласие.
      if (secondsLeft <= 0 && !_adMode) {
        if (!_adConsentShown) {
          _adConsentShown = true;
          final ok = await (onNeedAdConsent?.call() ?? Future.value(false));
          if (ok) {
            _enableAdMode(); // включает расписание рекламы и отключает списание секунд
          } else {
            // Пользователь уже увидел экран выбора (reward/ads-mode) и отменил.
            // Не показываем второй раз подряд, просто выходим из play().
            return;
          }
        } else {
          // экран уже показывали и отказались → просто не стартуем
          onCreditsExhausted?.call();
          return;
        }
      } else if (secondsLeft > 0) {
        // На всякий случай снимаем флаг «исчерпано», если секунды вернулись.
        _creditsConsumer?.resetExhaustion();
      }
    }

    await player.play();

    if (_adMode) {
      _syncAdScheduleWithPlayback();
    } else {
      _creditsConsumer?.start(); // обычное списание для free с секундами
    }

    rearmFreeSecondsTickerSafely();
    notifyListeners();
  }

  Future<void> pause({bool fromConnectivity = false}) async {
    if (!fromConnectivity) {
      _pausedByConnectivity = false;
    }
    await player.pause();
    _creditsConsumer?.stop();
    _serverPushTimer?.cancel();
    _stopFreeSecondsTicker();

    _stopAdTimer(); // === AD-MODE FIX

    _saveProgressThrottled(force: true);
    await _pushProgressToServer(force: true, allowZero: false);
    notifyListeners();
  }

  Future<void> stop() async {
    await player.stop();
    _creditsConsumer?.stop();
    _serverPushTimer?.cancel();
    _stopFreeSecondsTicker();

    _stopAdTimer(); // === AD-MODE FIX

    _saveProgressThrottled(force: true);
    await _pushProgressToServer(force: true, allowZero: false);
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(
      Duration position, {
        bool persist = true,
      }) async {
    if (!_hasSequence) return;

    await player.seek(position);
    _position = position;

    final sec = position.inSeconds;
    if (persist && sec > 0) {
      _saveProgressThrottled(force: true);
      await _pushProgressToServer(force: true, allowZero: false);
    }

    _rearmFreeSecondsTicker();
    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 3.0);
    await player.setSpeed(_speed);
    _rearmFreeSecondsTicker();
    notifyListeners();
  }

  Future<void> nextChapter() async {
    if (!_hasSequence || _currentChapterIndex + 1 >= _chapters.length) return;

    if (_position.inSeconds > 0) {
      _saveProgressThrottled(force: true);
      await _pushProgressToServer(force: true, allowZero: false);
    }

    await player.seek(Duration.zero, index: _currentChapterIndex + 1);
    _position = Duration.zero;
    _lastPushSig = null;

    _rearmFreeSecondsTicker();
    await player.play();
  }

  Future<void> previousChapter() async {
    if (!_hasSequence || _currentChapterIndex - 1 < 0) return;

    if (_position.inSeconds > 0) {
      _saveProgressThrottled(force: true);
      await _pushProgressToServer(force: true, allowZero: false);
    }

    await player.seek(Duration.zero, index: _currentChapterIndex - 1);
    _position = Duration.zero;
    _lastPushSig = null;

    _rearmFreeSecondsTicker();
    await player.play();
  }

  Future<void> seekChapter(
      int index, {
        Duration? position,
        bool persist = true,
      }) async {
    if (!(index >= 0 && index < _chapters.length && _hasSequence)) return;

    final isChapterChange = index != _currentChapterIndex;
    final newPos = position ?? Duration.zero;

    if (isChapterChange && _position.inSeconds > 0) {
      _saveProgressThrottled(force: true);
      await _pushProgressToServer(force: true, allowZero: false);
    }

    _log('seekChapter($index, pos=${newPos.inSeconds})');
    await player.seek(newPos, index: index);
    _position = newPos;
    _lastPushSig = null;

    if (persist && newPos.inSeconds > 0) {
      _saveProgressThrottled(force: true);
      await _pushProgressToServer(force: true, allowZero: false);
    }

    _rearmFreeSecondsTicker();
    notifyListeners();
  }

  // ---------- ПОДГОТОВКА / ВОССТАНОВЛЕНИЕ (FIX: Загрузка полного плейлиста для авторизованных) ----------
  Future<bool> _prepareFromSavedIfNeeded() async {
    if (_hasSequence) return true;
    if (_isPreparing) {
      while (_isPreparing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _hasSequence;
    }

    _isPreparing = true;
    try {
      if (currentBook == null || currentChapter == null) {
        await restoreProgress();
      }
      if (currentBook == null || currentChapter == null) {
        final ok = await _hydrateFromServerIfAvailable();
        if (!ok) {
          _log('_prepare: no saved session at all');
          return false;
        }
      }

      final ch = currentChapter;
      final b = currentBook;
      if (ch == null || b == null) return false;

      UserType effectiveUserType = _userType;

      if (_userType == UserType.guest && AuthStore.I.isLoggedIn) {
        final cachedProfile = ProfileRepository.I.getCachedMap();
        if (cachedProfile != null) {
          final userMap = (cachedProfile['user'] is Map<String, dynamic>)
              ? Map<String, dynamic>.from(cachedProfile['user'] as Map)
              : Map<String, dynamic>.from(cachedProfile);
          final derived = getUserType(User.fromJson(userMap));
          _log('_prepare: logged-in token, cached profile → userType=$derived');
          effectiveUserType = derived;
        } else {
          _log('_prepare: logged-in token, no cached profile → assume FREE for resume');
          effectiveUserType = UserType.free;
        }
      }

      List<Chapter> chaptersToLoad;
      int startIndex = 0;

      // 🔥 4. СОХРАНЯЕМ ТЕКУЩУЮ ПОЗИЦИЮ ПЕРЕД ВЫЗОВОМ SETCHAPTERS
      final posToRestore = _position;

      // Логіка гостя (тільки перша глава)
      if (effectiveUserType == UserType.guest) {
        final o = ch.order ?? 1;
        if (o > 1) {
          _log('_prepare: guest + saved non-first chapter → очищаем сохранённое');
          await saveCurrentListenToPrefs(book: null, chapter: null, position: 0);
          _resetState();
          return false;
        }
        chaptersToLoad = [ch];
        startIndex = 0;
      } else {
        // Для авторизованных: загружаем полный список.

        // 🔥 ИЗМЕНЕНИЕ НАЧАЛО: Пробуем кэш, потом сеть
        List<Chapter> fullList = await _getCachedChaptersForBook(b.id);

        if (fullList.isNotEmpty) {
          _log('_prepare: using CACHED chapter list (${fullList.length})');
        } else {
          _log('_prepare: cache miss, fetching from network...');
          fullList = await _retrieveAllChaptersForBook(b.id);
        }
        // 🔥 ИЗМЕНЕНИЕ КОНЕЦ

        if (fullList.isEmpty) {
          _log('_prepare: failed to fetch full chapter list for book ${b.id}, defaulting to single saved chapter');
          chaptersToLoad = [ch];
          startIndex = 0;
        } else {
          chaptersToLoad = fullList;
          // Находим индекс главы, с которой остановились, в полном списке.
          startIndex = fullList.indexWhere((c) => c.id == ch.id);
          if (startIndex < 0) {
            _log('_prepare: last listened chapter not found in full list, starting at first chapter');
            startIndex = 0;
          }
        }
      }

      final cover = _absImageUrl(b.displayCoverUrl);

      // 🔥 5. ПЕРЕДАЕМ ПОЗИЦИЮ В SETCHAPTERS
      await setChapters(
        chaptersToLoad,
        startIndex: startIndex,
        book: b,
        bookTitle: b.title,
        artist: b.author,
        coverUrl: cover,
        userTypeOverride: effectiveUserType,
        ignoreSavedPosition: true,
        initialPositionOverride: posToRestore, // <--- Важно
      );

      // 🔥 6. УДАЛЕН БЛОК SEEK. Теперь инициализация атомарна.

      return true;
    } finally {
      _isPreparing = false;
    }
  }

  Future<void> restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kCurrentListenKey);
    if (jsonStr == null) {
      _log('restoreProgress: empty SharedPreferences');
      return;
    }

    try {
      final data = json.decode(jsonStr);
      final bookJson = data['book'] as Map<String, dynamic>;
      final chapterJson = data['chapter'] as Map<String, dynamic>;
      final position = data['position'] ?? 0;

      final book = Book.fromJson(bookJson);
      final chapter = Chapter.fromJson(chapterJson, book: bookJson);

      _chapters = [
        Chapter(
          id: chapter.id,
          title: chapter.title,
          order: chapter.order,
          audioUrl: _normalizeAudioUrl(chapter.audioUrl) ?? '',
          duration: chapter.duration,
          book: chapter.book,
        )
      ];
      _currentChapterIndex = 0;
      _position = Duration(
          seconds: position is int ? position : int.tryParse('$position') ?? 0);
      _duration = Duration(seconds: chapter.duration ?? 0);

      await _writeProgressEntry(
        bookId: book.id,
        chapterId: chapter.id,
        positionSec: _position.inSeconds,
      );

      _log('restoreProgress: ok (pos=${_position.inSeconds})');
    } catch (e) {
      _log('restoreProgress: error: $e');
    }
  }

  // ---------- UI helpers ----------
  Future<bool> handleBottomPlayTap() async {
    _log('handleBottomPlayTap()');
    final prepared = await _prepareFromSavedIfNeeded();
    if (!prepared) return false;

    await ensureCreditsTickerBound();

    if (player.playing) {
      await pause();
    } else {
      await play();
    }

    rearmFreeSecondsTickerSafely();
    return true;
  }

  void _setCurrent({
    required Book book,
    required Chapter chapter,
    required int positionSec,
  }) {
    _chapters = [
      Chapter(
        id: chapter.id,
        title: chapter.title,
        order: chapter.order,
        audioUrl: _normalizeAudioUrl(chapter.audioUrl) ?? '',
        duration: chapter.duration,
        book: chapter.book ?? book.toJson(),
      )
    ];
    _currentChapterIndex = 0;
    _position = Duration(seconds: positionSec);
    _duration = Duration(seconds: chapter.duration ?? 0);
  }

  // ======== Drag-помощники для слайдера ========
  void seekDragStart() {
    _isUserSeeking = true;
  }

  void seekDragUpdate(Duration pos) {
    _uiPositionOverride = pos;
    notifyListeners();
  }

  Future<void> seekDragEnd(Duration pos) async {
    _isUserSeeking = false;
    final wasOverride = _uiPositionOverride;
    _uiPositionOverride = null;
    await seek(pos);
    if (wasOverride != null) {
      _position = pos;
      notifyListeners();
    }
  }

  // === AD-MODE: PUBLIC API ===
  Future<void> enableAdsMode({bool keepPlaying = true}) async {
    _enableAdMode();
    if (keepPlaying && !player.playing) {
      await player.play();
    }
    _syncAdScheduleWithPlayback();
    notifyListeners();
  }

  void disableAdsMode() => _disableAdMode();

  void suspendAdSchedule(String reason) {
    _adScheduleSuspend++;
    _log('suspend ad-schedule ($reason) count=$_adScheduleSuspend');
    _stopAdTimer();
  }

  void resumeAdSchedule(String reason) {
    if (_adScheduleSuspend > 0) _adScheduleSuspend--;
    _log('resume ad-schedule ($reason) count=$_adScheduleSuspend');
    _syncAdScheduleWithPlayback();
  }

  void _enableAdMode() {
    final secondsLeft = getFreeSeconds?.call() ?? 0;
    if (secondsLeft > 0) {
      _log('skip ad-mode: balance=${secondsLeft}s');
      return;
    }

    if (_adMode) return;
    _log('enable ad-mode');
    _adMode = true;
    _creditsConsumer?.stop();
    // 🔥 При включении сбрасываем таймер на полный интервал
    _remainingAdDuration = _adInterval;
    _syncAdScheduleWithPlayback();
    notifyListeners();
  }

  void _disableAdMode() {
    if (!_adMode) return;
    _log('disable ad-mode');
    _adMode = false;
    _stopAdTimer();
    _ensureCreditsConsumer();
    notifyListeners();
  }

  void _syncAdScheduleWithPlayback() {
    if (_adMode && player.playing && !isAdScheduleSuspended) {
      _scheduleNextAd();
    } else {
      _stopAdTimer();
    }
  }

  // 🔥 Пауза таймера: сохраняем остаток
  void _stopAdTimer() {
    _adTimer?.cancel();
    _adTimer = null;

    if (_adTargetTime != null) {
      final now = DateTime.now();
      final left = _adTargetTime!.difference(now);
      // Если время вышло, но реклама не успела показаться — будет 0
      _remainingAdDuration = left.isNegative ? Duration.zero : left;
      _adTargetTime = null;
    }
  }

  // 🔥 Запуск таймера: используем остаток
  void _scheduleNextAd() {
    if (!_adMode) return;
    if (isAdScheduleSuspended) {
      _log('ad schedule suspended → skip scheduling');
      _stopAdTimer();
      return;
    }

    // Если уже запущен — не трогаем
    if (_adTimer != null && _adTimer!.isActive) return;

    final delay = _remainingAdDuration;

    _adTargetTime = DateTime.now().add(delay);
    _log('ad scheduled in ${delay.inSeconds}s');

    _adTimer = Timer(delay, () async {
      // Проверка фона
      final appState = WidgetsBinding.instance.lifecycleState;
      final bool isForeground = appState == AppLifecycleState.resumed;

      if (!isForeground) {
        _log('Ad timer fired in BACKGROUND. Pausing player instead of showing ad.');
        await pause();
        _pendingAdDueToBackground = true;
        return;
      }

      if (_adMode && _isPlayingAudibly() && !isAdScheduleSuspended) {
        // 🔥 FIX 1: Сбрасываем цели
        _adTargetTime = null;

        // 🔥 FIX 2: Сбрасываем таймер ЗАРАНЕЕ, до вызова рекламы.
        // Это предотвращает зацикливание, если play() будет вызван внутри колбека рекламы.
        _remainingAdDuration = _adInterval;

        // Включаем "Загрузка"
        _isAdLoading = true;
        notifyListeners();

        try {
          await onShowIntervalAd?.call();
        } catch (e) {
          _log('show ad error: $e');
        } finally {
          _isAdLoading = false;
          // 🔥 СБРОС ТАЙМЕРА ПОСЛЕ ПОКАЗА, ЧТОБЫ НЕ БЫЛО ЦИКЛА
          _lastAdAt = DateTime.now();
          // _remainingAdDuration уже сброшен выше.
          notifyListeners();
        }
      } else {
        _lastAdAt = DateTime.now();
        // Если не показали — всё равно сбрасываем на след. интервал
        _remainingAdDuration = _adInterval;
      }

      if (_adMode && player.playing && !isAdScheduleSuspended) {
        _scheduleNextAd();
      } else {
        _stopAdTimer();
      }
    });
  }

  // --- ЛОКАЛЬНЫЙ КЭШ ГЛАВ (ДЛЯ МГНОВЕННОГО СТАРТА) ---

  Future<void> _cacheChaptersForBook(int bookId, List<Chapter> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Превращаем список объектов в список JSON-строк
      final jsonList = list.map((c) => c.toJson()).toList();
      await prefs.setString('$_kChaptersCachePrefix$bookId', json.encode(jsonList));
    } catch (e) {
      _log('cacheChapters error: $e');
    }
  }

  Future<List<Chapter>> _getCachedChaptersForBook(int bookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kChaptersCachePrefix$bookId');
      if (raw == null) return [];

      final List<dynamic> jsonList = json.decode(raw);
      return jsonList.map((item) {
        // Важно передать bookId, так как в JSON главы его может не быть
        return Chapter.fromJson(
          Map<String, dynamic>.from(item as Map),
          book: {'id': bookId},
        );
      }).toList();
    } catch (e) {
      _log('getCachedChapters error: $e');
      return [];
    }
  }

  // --- НОВЫЙ МЕТОД: Показать "зависшую" рекламу при возврате из фона ---
  Future<void> checkPendingAdOnResume() async {
    if (_pendingAdDueToBackground) {
      _log('Resumed with pending ad -> Show NOW');
      _pendingAdDueToBackground = false;

      _isAdLoading = true;
      notifyListeners();

      try {
        await onShowIntervalAd?.call();
      } catch (e) {
        _log('show pending ad error: $e');
      } finally {
        _isAdLoading = false;
        _lastAdAt = DateTime.now();
        _remainingAdDuration = _adInterval;
        notifyListeners();
      }

      if (_adMode) {
        await play();
      }
    }
  }

  @override
  void dispose() {
    _serverPushTimer?.cancel();
    _pendingRearmTimer?.cancel();
    _creditsConsumer?.stop();
    _stopFreeSecondsTicker();
    _stopAdTimer();
    _connectivitySub?.cancel();
    player.dispose();
    super.dispose();
  }
}
