// lib/providers/audio_player_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/user.dart'; // enum UserType, getUserType
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth/auth_store.dart'; // ← правильный путь
import 'package:booka_app/constants.dart'; // fullResourceUrl для нормализации относительных путей

// ✅ единая точка загрузки профиля вместо /profile
import 'package:booka_app/repositories/profile_repository.dart';

// ---- КЛЮЧИ ДЛЯ PREFS ----
const String _kCurrentListenKey = 'current_listen';
const String _kProgressMapKey = 'listen_progress_v1';

// ==== helpers для времени
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
  DateTime? updatedAt, // ← НОВОЕ: сохраняем метку времени
}) async {
  final prefs = await SharedPreferences.getInstance();

  if (book == null || chapter == null) {
    await prefs.remove(_kCurrentListenKey);
    if (kDebugMode) debugPrint('saveCurrentListen: CLEARED');
    return;
  }

  // Расширенный формат с явными id и updated_at (обратная совместимость сохранена)
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

// ---------- ЛОКАЛЬНАЯ ЗАГРУЗКА CL ДЛЯ LWW (вынесено на верхний уровень) ----------
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

  double _speed = 1.0;
  List<Chapter> _chapters = [];
  int _currentChapterIndex = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // троттлинг сохранения прогресса (локально)
  DateTime? _lastPersistAt;
  final Duration _persistEvery = const Duration(seconds: 10);

  // коалессация подготовки/гидратации
  bool _isPreparing = false;
  bool _hydrating = false;
  Completer<bool>? _hydrateCompleter;
  DateTime? _lastHydrate401At;

  // in-memory кэш для listen_progress_v1
  Map<String, dynamic>? _progressMapCache;

  // ======= PUSH прогресса на API ======= и дебаунс
  Timer? _serverPushTimer;
  String? _lastPushSig; // "bookId:chapterId:pos"
  final Duration _pushDelay = const Duration(seconds: 5);
  static const int _minAutoPushSec = 2; // не шлём 0/1с автоматически

  UserType _userType = UserType.guest;
  UserType get userType => _userType;
  set userType(UserType value) {
    _log('userType := $value');
    _userType = value;
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

  /// Запрошено UI: текущий URL аудиопотока.
  String? get currentUrl => currentChapter?.audioUrl;

  bool get _hasSequence => (player.sequenceState?.sequence.isNotEmpty ?? false);

  AudioPlayerProvider() {
    // Позиция
    player.positionStream.listen((pos) {
      if (!_hasSequence) return; // источник ещё не готов → игнор

      // ВАЖНО: не затираем уже известную положительную позицию нулём,
      // т.к. после setAudioSource могут прилететь единичные Duration.zero
      if (_position > Duration.zero && pos == Duration.zero) {
        return;
      }

      _position = pos;
      _saveProgressThrottled();
      _scheduleServerPush(); // отправка на сервер (дебаунс, без ранних нулей)
      notifyListeners();
    });

    // Длительность текущего элемента
    player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    // На смене последовательности — подстрахуемся по длительности
    player.sequenceStateStream.listen((_) => _pullDurationFromPlayer());

    // Переключение главы
    player.currentIndexStream.listen((idx) {
      if (idx != null && idx >= 0 && idx < _chapters.length) {
        _currentChapterIndex = idx;

        // НЕ обнуляем позицию — берём фактическую у плеера
        _position = player.position;

        _lastPushSig = null; // новая глава → разрешим следующий пуш
        _pullDurationFromPlayer();
        notifyListeners();
      }
    });

    // Скорость
    player.speedStream.listen((s) {
      _speed = s;
      notifyListeners();
    });

    // Конец трека/главы
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _saveProgressThrottled(force: true);
        _pushProgressToServer(force: true); // завершили — пушим немедленно

        // *** ИСПРАВЛЕНИЕ #1: Логика переключения глав ***
        final hasNext = _currentChapterIndex + 1 < _chapters.length;

        if (_userType == UserType.guest) {
          _log('ProcessingState.completed for GUEST — stopping');
          _onGuestFirstChapterEnd?.call();
          player.stop();
          return;
        }

        if (hasNext) {
          nextChapter();
        } else {
          player.stop();
        }
      }
    });
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[AUDIO] $msg');
  }

  void _pullDurationFromPlayer() {
    final d = player.duration;
    _duration = d ?? Duration.zero;
  }

  // ... (весь остальной код до функции _sourceForChapter остается без изменений)

  // ... (код с _readProgressMap до _fetchChapterById)
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
    } catch (_) {
      // ignore
    }
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
      chapterId ??= (chapterJson?['id'] is int)
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
        bookId: b.id, chapterId: ch.id, positionSec: posSec);
  }

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
    if (s.startsWith('http')) return s;
    final path = s.startsWith('storage/')
        ? s
        : (s.startsWith('/storage/') ? s.substring(1) : 'storage/$s');
    return fullResourceUrl(path);
  }

  Future<Chapter?> _fetchChapterById(int bookId, int chapterId) async {
    try {
      final resp = await ApiClient.i().get(
        '/abooks/$bookId/chapters',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (resp.statusCode != 200) return null;

      final raw = resp.data;
      final List<dynamic> items = (raw is List)
          ? raw
          : (raw is Map<String, dynamic>)
          ? (raw['data'] ?? raw['items'] ?? [])
          : [];

      for (final it in items) {
        final ch = Chapter.fromJson(
          Map<String, dynamic>.from(it as Map),
          book: {'id': bookId},
        );
        if (ch.id == chapterId) return ch;
      }
    } catch (_) {}
    return null;
  }

  AudioSource _sourceForChapter(
      Chapter chapter, {
        String? prettyTitle,
        String? artist,
        String? coverUrl,
      }) {
    final title = (prettyTitle != null && prettyTitle.isNotEmpty)
        ? prettyTitle
        : (chapter.title.isNotEmpty ? chapter.title : 'Глава');

    final normalizedUrl = _normalizeAudioUrl(chapter.audioUrl);

    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      throw StateError('Chapter ${chapter.id} has no valid audioUrl');
    }

    // *** ИСПРАВЛЕНИЕ #2: Включаем передачу заголовков авторизации ***
    return AudioSource.uri(
      Uri.parse(Uri.encodeFull(normalizedUrl)),
      headers: _authHeaders(), // ← РАСКОММЕНТИРОВАНО
      tag: MediaItem(
        id: chapter.id.toString(),
        title: title,
        artist: artist ?? 'Неизвестно',
        artUri: (coverUrl != null && coverUrl.isNotEmpty)
            ? Uri.parse(coverUrl)
            : null,
        duration: (chapter.duration != null && chapter.duration! > 0)
            ? Duration(seconds: chapter.duration!)
            : null,
      ),
    );
  }

  // ... (весь остальной код, начиная с _playlistFromChapters и до конца файла, остается без изменений)
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
      );
    }).toList();
    return ConcatenatingAudioSource(children: children);
  }

  Future<bool> hydrateFromServerIfAvailable() =>
      _hydrateFromServerIfAvailable();

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
      _lastHydrate401At = DateTime.now();
      _log('hydrate: not logged in → skip');
      return false;
    }

    if (_userType == UserType.guest && _lastHydrate401At != null) {
      final ago = DateTime.now().difference(_lastHydrate401At!);
      if (ago < const Duration(seconds: 60)) {
        _log('hydrate: skip (recent 401 ${ago.inSeconds}s ago)');
        return false;
      }
    }

    if (_hydrating) {
      return _hydrateCompleter!.future;
    }

    _hydrating = true;
    _hydrateCompleter = Completer<bool>();
    try {
      final local = await _loadLocalCL();

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
          data['currentListening'])
      as Map?;

      final serverNow = _parseUtc(data['server_time']) ?? _nowUtc();

      Future<void> _applyServerCL(Map<String, dynamic> clMap) async {
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
        final int pos =
        (pRaw is int) ? pRaw : int.tryParse(pRaw.toString()) ?? 0;

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
                book = Book.fromJson(
                    {'id': bookId, 'title': '', 'author': ''});
              }
            }
          }
        }

        if (book == null || chapter == null) {
          _log('hydrate: applyServerCL missing book/chapter json — skip');
          return;
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
            bookId: bookId, chapterId: normalized.id, positionSec: pos);

        _chapters = [normalized];
        _currentChapterIndex = 0;
        _position = Duration(seconds: pos);
        _duration = Duration(seconds: normalized.duration ?? 0);

        _log(
            'hydrate: applied server (book=$bookId, ch=${normalized.id}, pos=$pos, upd=$upd)');
        notifyListeners();
      }

      Future<void> _pushLocalUp(_LocalCL localCL) async {
        if (localCL.bookId == null || localCL.chapterId == null) return;
        if (localCL.position <= 0) {
          _log('hydrate: local newer but position=0 → skip push');
          return;
        }
        try {
          final resp2 = await ApiClient.i().post(
            '/listens',
            data: {
              'a_book_id': localCL.bookId,
              'a_chapter_id': localCL.chapterId,
              'position': localCL.position,
            },
            options: Options(validateStatus: (s) => s != null && s < 500),
          );
          if (resp2.statusCode == 404) {
            await ApiClient.i().post(
              '/listen/update',
              data: {
                'a_book_id': localCL.bookId,
                'a_chapter_id': localCL.chapterId,
                'position': localCL.position,
              },
              options:
              Options(validateStatus: (s) => s != null && s < 500),
            );
          }
          _log('hydrate: pushed local up (pos=${localCL.position})');
        } catch (e) {
          _log('hydrate: push local error: $e');
        }
      }

      if (srv == null && local == null) {
        _log('hydrate: nothing to sync (both empty)');
        _hydrateCompleter!.complete(false);
        return false;
      }

      if (srv == null && local != null) {
        await _pushLocalUp(local);
        _hydrateCompleter!.complete(true);
        return true;
      }

      if (srv != null && local == null) {
        await _applyServerCL(Map<String, dynamic>.from(srv));
        _hydrateCompleter!.complete(true);
        return true;
      }

      final srvMap = Map<String, dynamic>.from(srv!);
      final srvUpd = _parseUtc(srvMap['updated_at']) ?? serverNow;
      final locUpd = local!.updatedAt ?? _nowUtc();

      if (_isAfterWithSkew(srvUpd, locUpd)) {
        await _applyServerCL(srvMap);
      } else if (_isAfterWithSkew(locUpd, srvUpd)) {
        await _pushLocalUp(local);
      } else {
        final sameChapter = (srvMap['chapter_id']?.toString() ?? '') ==
            (local.chapterId?.toString() ?? '');
        final int srvPos = (srvMap['position'] is int)
            ? srvMap['position'] as int
            : int.tryParse('${srvMap['position']}') ?? 0;
        if (sameChapter) {
          final best =
          (local.position > srvPos) ? local.position : srvPos;

          try {
            await ApiClient.i().post(
              '/listens',
              data: {
                'a_book_id': local.bookId,
                'a_chapter_id': local.chapterId,
                'position': best,
              },
              options:
              Options(validateStatus: (s) => s != null && s < 500),
            );
          } catch (_) {
            try {
              await ApiClient.i().post(
                '/listen/update',
                data: {
                  'a_book_id': local.bookId,
                  'a_chapter_id': local.chapterId,
                  'position': best,
                },
                options: Options(
                    validateStatus: (s) => s != null && s < 500),
              );
            } catch (e) {
              _log('hydrate: tie push best error: $e');
            }
          }

          if (local.bookJson != null && local.chapterJson != null) {
            final book = Book.fromJson(local.bookJson!);
            final chapter = Chapter.fromJson(local.chapterJson!,
                book: local.bookJson);
            _setCurrent(
                book: book, chapter: chapter, positionSec: best);
            await saveCurrentListenToPrefs(
                book: book, chapter: chapter, position: best);
          }
        } else {
          await _applyServerCL(srvMap);
        }
      }

      _hydrateCompleter!.complete(true);
      return true;
    } catch (e) {
      _log('hydrate: error: $e');
      _hydrateCompleter!.complete(false);
      return false;
    } finally {
      _hydrating = false;
    }
  }

  Future<void> setChapters(
      List<Chapter> chapters, {
        int startIndex = 0,
        String? bookTitle,
        String? artist,
        String? coverUrl,
        Book? book,
      }) async {
    List<Chapter> playlistChapters = chapters;

    if (_userType == UserType.guest) {
      if (chapters.isEmpty) {
        _log('setChapters: guest — пустой список глав');
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
        _chapters
            .asMap()
            .entries
            .every((e) => e.value.id == playlistChapters[e.key].id);

    if (samePlaylist && _hasSequence) {
      _log('setChapters: same playlist — skip setAudioSource()');
      return;
    }

    int initialIndex = (_userType == UserType.guest) ? 0 : startIndex;
    Duration initialPos = Duration.zero;

    if (book != null) {
      final saved = await _getProgressForBook(book.id);
      if (saved != null) {
        final savedChapterId = saved['chapterId'];
        final savedPosSec = saved['position'] ?? 0;
        if (savedChapterId is int) {
          final idx =
          playlistChapters.indexWhere((c) => c.id == savedChapterId);
          if (idx >= 0) {
            initialIndex = idx;
            initialPos =
                Duration(seconds: savedPosSec is int ? savedPosSec : 0);
          } else {
            initialPos = Duration.zero;
          }
        }
      }
    } else {
      if (_position > Duration.zero && playlistChapters.length == 1) {
        initialPos = _position;
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

    final playlist = _playlistFromChapters(
      list: _chapters,
      bookTitle: bookTitle,
      artist: artist,
      coverUrl: coverUrl,
    );

    _log(
        'setChapters: ${_chapters.length} items, start=$_currentChapterIndex, initialPos=${initialPos.inSeconds}s');
    try {
      await player.setAudioSource(
        playlist,
        initialIndex: _currentChapterIndex,
        initialPosition: initialPos,
      );
    } catch (e) {
      _log('setChapters: setAudioSource error: $e');
      rethrow;
    }

    _position = initialPos;
    _pullDurationFromPlayer();
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
    notifyListeners();
  }

  Future<void> play() async {
    await player.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await player.pause();
    _serverPushTimer?.cancel();
    _saveProgressThrottled(force: true);
    await _pushProgressToServer(force: true, allowZero: false);
    notifyListeners();
  }

  Future<void> stop() async {
    await player.stop();
    _serverPushTimer?.cancel();
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

    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 3.0);
    await player.setSpeed(_speed);
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

    notifyListeners();
  }

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
      if (ch == null) return false;

      if (_userType == UserType.guest) {
        final o = ch.order ?? 1;
        if (o > 1) {
          _log('_prepare: guest + saved non-first chapter → очистка сохранённого');
          await saveCurrentListenToPrefs(book: null, chapter: null, position: 0);
          _resetState();
          return false;
        }
      }

      await setChapters([ch], startIndex: 0, book: b);
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
      _position = Duration(seconds: position is int ? position : int.tryParse('$position') ?? 0);
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

  Future<bool> handleBottomPlayTap() async {
    _log('handleBottomPlayTap()');
    final prepared = await _prepareFromSavedIfNeeded();
    if (!prepared) return false;

    if (player.playing) {
      await pause();
    } else {
      await play();
    }
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

  @override
  void dispose() {
    _serverPushTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}