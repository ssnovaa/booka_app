import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/chapter.dart';
import '../models/book.dart';
import '../models/user.dart';

// Enum для четкого определения состояния плеера
enum PlayerStatus { idle, loading, ready, error }

class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();

  // Состояние плеера
  PlayerStatus _status = PlayerStatus.idle;
  String? _error;
  double _speed = 1.0;

  // Данные о плейлисте
  Book? _currentBook;
  List<Chapter> _chapters = [];
  int _currentChapterIndex = 0;

  // Зависимости
  UserType _userType = UserType.guest;
  VoidCallback? onGuestFirstChapterEnd;

  // Геттеры для доступа из UI
  PlayerStatus get status => _status;
  bool get isPlaying => player.playing;
  double get speed => _speed;
  Book? get currentBook => _currentBook;
  List<Chapter> get chapters => _chapters;
  Chapter? get currentChapter => _chapters.isNotEmpty && _currentChapterIndex < _chapters.length
      ? _chapters[_currentChapterIndex]
      : null;

  // Потоки для реактивного UI
  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<bool> get playingStream => player.playingStream;

  AudioPlayerProvider() {
    _listenToPlayerState();
  }

  void _listenToPlayerState() {
    // Подписка на изменение текущей главы (индекса)
    player.currentIndexStream.listen((index) {
      if (index != null && index != _currentChapterIndex) {
        _currentChapterIndex = index;
        _saveProgress();
        notifyListeners();
      }
    });

    // Обработка окончания трека и плейлиста
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Если гость и прослушал единственную доступную главу
        if (_userType == UserType.guest && _chapters.length == 1) {
          onGuestFirstChapterEnd?.call();
        }
        _saveProgress(); // Сохраняем прогресс в конце главы
      }
    });
  }

  /// Главный метод для установки нового плейлиста
  Future<void> setBook(Book book, List<Chapter> chapters, {int startChapterId = 0, bool autoPlay = false}) async {
    // Проверяем, не проигрывается ли уже эта книга
    if (_currentBook?.id == book.id) {
      if (autoPlay && !player.playing) await play();
      return;
    }

    _status = PlayerStatus.loading;
    notifyListeners();

    try {
      _currentBook = book;
      _chapters = (_userType == UserType.guest && chapters.isNotEmpty) ? [chapters.first] : chapters;

      final startIndex = _chapters.indexWhere((c) => c.id == startChapterId);
      _currentChapterIndex = (startIndex != -1) ? startIndex : 0;

      final audioSources = _chapters.map((chapter) => _createAudioSource(chapter, book)).toList();

      if (audioSources.isEmpty) {
        throw Exception("Нет глав для воспроизведения.");
      }

      await player.setAudioSource(
        ConcatenatingAudioSource(children: audioSources),
        initialIndex: _currentChapterIndex,
        initialPosition: Duration.zero,
      );

      _status = PlayerStatus.ready;
      if (autoPlay) await player.play();

    } catch (e) {
      _error = e.toString();
      _status = PlayerStatus.error;
    } finally {
      notifyListeners();
    }
  }

  AudioSource _createAudioSource(Chapter chapter, Book book) {
    return AudioSource.uri(
      Uri.parse(Uri.encodeFull(chapter.audioUrl)),
      tag: MediaItem(
        id: chapter.id.toString(),
        title: chapter.title,
        album: book.title,
        artist: book.author,
        artUri: book.displayCoverUrl != null ? Uri.parse(book.displayCoverUrl!) : null,
        duration: (chapter.duration != null && chapter.duration! > 0)
            ? Duration(seconds: chapter.duration!)
            : null,
      ),
    );
  }

  // --- Управление воспроизведением ---

  Future<void> play() async => await player.play();
  Future<void> pause() async => await player.pause();
  Future<void> seek(Duration position) async => await player.seek(position);
  Future<void> seekToChapter(int index, {Duration position = Duration.zero}) async {
    if (index >= 0 && index < _chapters.length) {
      await player.seek(position, index: index);
    }
  }

  void changeSpeed() {
    const speeds = [1.0, 1.25, 1.5, 1.75, 2.0];
    final currentIndex = speeds.indexOf(_speed);
    _speed = speeds[(currentIndex + 1) % speeds.length];
    player.setSpeed(_speed);
    notifyListeners();
  }

  // --- Сохранение и восстановление прогресса ---

  Future<void> _saveProgress() async {
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_listen', json.encode({
      'book': book.toJson(),
      'chapter': chapter.toJson(),
      'position': player.position.inSeconds,
    }));
  }

  // Вызывать при старте приложения
  Future<void> restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('current_listen');
    if (jsonStr == null) return;

    try {
      final data = json.decode(jsonStr);
      final book = Book.fromJson(data['book']);
      final chapter = Chapter.fromJson(data['chapter'], book: book);
      final position = Duration(seconds: data['position'] ?? 0);

      // Устанавливаем книгу, но не запускаем автопроигрывание
      await setBook(book, [chapter], startChapterId: chapter.id);
      if (status == PlayerStatus.ready) {
        await seek(position);
      }
    } catch (e) {
      // Ошибка при восстановлении, ничего страшного
    }
  }

  // --- Публичные сеттеры ---
  void updateUserType(UserType newUserType) {
    _userType = newUserType;
    // Можно добавить логику обновления плейлиста, если тип пользователя изменился
    // во время прослушивания
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
