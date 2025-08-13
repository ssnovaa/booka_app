// lib/providers/audio_player_provider.dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:booka_app/models/chapter.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/user.dart'; // enum UserType

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

  UserType _userType = UserType.guest;
  set userType(UserType value) {
    _userType = value;
  }

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
    player.positionStream.listen((pos) {
      _position = pos;
      _saveProgress();
      notifyListeners();
    });

    player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    player.playingStream.listen((_) {
      notifyListeners();
    });

    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _chapters.length) {
        _currentChapterIndex = index;
        _saveProgress();
        notifyListeners();
      }
    });

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

  void _saveProgress() {
    saveCurrentListenToPrefs(
      book: currentBook,
      chapter: currentChapter,
      position: _position.inSeconds,
    );
  }

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
      // ignore
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
    final playlistChapters = _userType == UserType.guest
        ? (chapters.isNotEmpty ? [chapters.first] : <Chapter>[])
        : chapters;

    if (_chapters.isNotEmpty &&
        _chapters.length == playlistChapters.length &&
        _chapters.asMap().entries.every((entry) => entry.value.id == playlistChapters[entry.key].id)) {
      return;
    }

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
          artUri: (coverUrl != null && coverUrl.isNotEmpty) ? Uri.parse(coverUrl) : null,
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

  Future<void> nextChapter() async {
    if (_currentChapterIndex < _chapters.length - 1) {
      await player.seek(Duration.zero, index: _currentChapterIndex + 1);
      _saveProgress();
    }
  }

  Future<void> previousChapter() async {
    if (_currentChapterIndex > 0) {
      await player.seek(Duration.zero, index: _currentChapterIndex - 1);
      _saveProgress();
    }
  }

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
