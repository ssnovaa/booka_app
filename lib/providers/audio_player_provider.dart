import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/chapter.dart';
import '../models/book.dart';
import '../models/user.dart'; // enum UserType

// --- Функция сохранения прогресса (SharedPreferences) ---
Future<void> saveCurrentListenToPrefs({
  required Book? book,
  required Chapter? chapter,
  required int position,
}) async {
  if (book == null || chapter == null) return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('current_listen', json.encode({
    'book': book.toJson(),
    'chapter': chapter.toJson(),
    'position': position,
  }));
}

class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();

  double _speed = 1.0;
  List<Chapter> _chapters = [];
  int _currentChapterIndex = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // --- Контроль типа пользователя ---
  UserType _userType = UserType.guest;
  set userType(UserType value) {
    _userType = value;
  }

  // --- Callback для UI: показывать окно регистрации при окончании главы у guest ---
  void Function()? _onGuestFirstChapterEnd;
  set onGuestFirstChapterEnd(void Function()? cb) => _onGuestFirstChapterEnd = cb;

  bool get isPlaying => player.playing;
  double get speed => _speed;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get currentUrl =>
      _chapters.isNotEmpty ? _chapters[_currentChapterIndex].audioUrl : null;

  Chapter? get currentChapter =>
      _chapters.isNotEmpty ? _chapters[_currentChapterIndex] : null;

  Book? get currentBook =>
      _chapters.isNotEmpty && _chapters[_currentChapterIndex].book != null
          ? Book.fromJson(_chapters[_currentChapterIndex].book!)
          : null;

  List<Chapter> get chapters => _chapters;

  AudioPlayerProvider() {
    // Подписка на изменение позиции
    player.positionStream.listen((pos) {
      _position = pos;
      _saveProgress();
      notifyListeners();
    });

    // Подписка на изменение длительности
    player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    // Изменение статуса воспроизведения
    player.playingStream.listen((_) {
      notifyListeners();
    });

    // Подписка на изменение текущей главы (индекса)
    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _chapters.length) {
        _currentChapterIndex = index;
        _saveProgress();
        notifyListeners();
      }
    });

    // --- Callback для guest: окончание главы
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _userType == UserType.guest &&
          _chapters.length == 1) {
        if (_onGuestFirstChapterEnd != null) {
          _onGuestFirstChapterEnd!();
        }
      }
    });
  }

  /// Внутренняя функция для сохранения прогресса (текущее состояние)
  void _saveProgress() {
    saveCurrentListenToPrefs(
      book: currentBook,
      chapter: currentChapter,
      position: _position.inSeconds,
    );
  }

  /// Восстановление прогресса из SharedPreferences при запуске (вызывай в main/initState!)
  Future<void> restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('current_listen');
    if (jsonStr == null) return;

    try {
      final data = json.decode(jsonStr);
      final bookJson = data['book'] as Map<String, dynamic>;
      final chapterJson = data['chapter'] as Map<String, dynamic>;
      final position = data['position'] ?? 0;

      final book = Book.fromJson(bookJson);
      final chapter = Chapter.fromJson(chapterJson, book: bookJson);

      _chapters = [chapter];
      _currentChapterIndex = 0;
      _position = Duration(seconds: position);
      _duration = Duration(seconds: chapter.duration ?? 0);

      notifyListeners();
    } catch (e) {
      // ignore, ничего не делаем если данные битые
    }
  }

  /// Загружает главы как плейлист. Для guest — только первая!
  Future<void> setChapters(
      List<Chapter> chapters, {
        int startIndex = 0,
        String? bookTitle,
        String? artist,
        String? coverUrl,
        Book? book,
      }) async {
    // --- Ограничение: если гость, то только первая глава в плеере ---
    final playlistChapters = _userType == UserType.guest
        ? (chapters.isNotEmpty ? [chapters.first] : <Chapter>[])
        : chapters;

    // Проверка на совпадение, чтобы не сбрасывать проигрыватель попусту
    if (_chapters.isNotEmpty &&
        _chapters.length == playlistChapters.length &&
        _chapters.asMap().entries.every((entry) => entry.value.id == playlistChapters[entry.key].id)) {
      return;
    }

    // ДОБАВЛЯЕМ book в каждую главу (важно для восстановления!)
    _chapters = playlistChapters
        .map((ch) => Chapter(
      id: ch.id,
      title: ch.title,
      order: ch.order,
      audioUrl: ch.audioUrl,
      duration: ch.duration,
      book: book != null ? book.toJson() : ch.book,
    ))
        .toList();

    _currentChapterIndex = startIndex;

    final sources = _chapters.map((chapter) {
      final prettyTitle = (bookTitle != null && bookTitle.isNotEmpty)
          ? '$bookTitle — ${chapter.title}'
          : chapter.title;
      return AudioSource.uri(
        Uri.parse(Uri.encodeFull(chapter.audioUrl)),
        tag: MediaItem(
          id: chapter.id.toString(),
          title: prettyTitle,
          artist: artist ?? "Неизвестно",
          artUri: (coverUrl != null && coverUrl.isNotEmpty)
              ? Uri.parse(coverUrl)
              : null,
          duration: (chapter.duration != null && chapter.duration! > 0)
              ? Duration(seconds: chapter.duration!)
              : null,
        ),
      );
    }).toList();

    await player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex,
      initialPosition: Duration.zero,
    );

    _position = Duration.zero;
    _duration = player.duration ?? Duration.zero;
    _saveProgress();
    notifyListeners();
  }

  Future<void> play() async {
    await player.play();
    _saveProgress();
  }

  Future<void> pause() async {
    await player.pause();
    _saveProgress();
  }

  Future<void> togglePlayback() async {
    if (player.playing) {
      await pause();
    } else {
      await play();
    }
    _saveProgress();
  }

  Future<void> seekTo(Duration position) async {
    await player.seek(position);
    _position = position;
    _saveProgress();
    notifyListeners();
  }

  void changeSpeed() {
    final List<double> speeds = [1.0, 1.25, 1.5, 1.75, 2.0];
    final currentIndex = speeds.indexOf(_speed);
    _speed = speeds[(currentIndex + 1) % speeds.length];
    player.setSpeed(_speed);
    _saveProgress();
    notifyListeners();
  }

  /// Переход к следующей главе
  Future<void> nextChapter() async {
    if (_currentChapterIndex < _chapters.length - 1) {
      await player.seek(Duration.zero, index: _currentChapterIndex + 1);
      _saveProgress();
    }
  }

  /// Переход к предыдущей главе
  Future<void> previousChapter() async {
    if (_currentChapterIndex > 0) {
      await player.seek(Duration.zero, index: _currentChapterIndex - 1);
      _saveProgress();
    }
  }

  /// Перейти к главе по индексу
  Future<void> seekChapter(int index, {Duration? position}) async {
    if (index >= 0 && index < _chapters.length) {
      await player.seek(position ?? Duration.zero, index: index);
      _saveProgress();
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
