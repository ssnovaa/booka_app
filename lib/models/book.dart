// ПУТЬ: lib/models/book.dart
import 'package:flutter/foundation.dart'; // для debugPrint

class Book {
  final int id;
  final String title;
  final String author;
  final String? reader;
  final String? description;

  /// Полный URL обложки (может отсутствовать)
  final String? coverUrl;

  /// Миниатюра (может отсутствовать). При наличии используем её в карточках.
  final String? thumbUrl;

  /// ВАЖНО: у тебя duration — всегда String (оставляем так)
  final String duration;

  /// Жанры приводим к List<String>
  final List<String> genres;

  final String? series;

  /// Быстрый признак: используется ли миниатюра
  bool get isThumbUsed => (thumbUrl ?? '').trim().isNotEmpty;

  /// Единая точка доступа к изображению:
  /// отдаёт thumbUrl, если есть, иначе coverUrl, иначе пустую строку.
  /// Плюс подробные логи в консоль (видно в Run/Debug Android Studio).
  String get displayCoverUrl {
    final t = (thumbUrl ?? '').trim();
    if (t.isNotEmpty) {
      debugPrint('[BookaApp] "$title" → ЗАГРУЖАЕТСЯ МИНИАТЮРА: $t');
      return t;
    }
    final c = (coverUrl ?? '').trim();
    if (c.isNotEmpty) {
      debugPrint('[BookaApp] "$title" → ЗАГРУЖАЕТСЯ ОБЛОЖКА: $c');
      return c;
    }
    debugPrint('[BookaApp] "$title" → НЕТ ИЗОБРАЖЕНИЯ');
    return '';
  }

  Book({
    required this.id,
    required this.title,
    required this.author,
    this.reader,
    this.description,
    this.coverUrl,
    this.thumbUrl,
    required this.duration,
    this.genres = const [],
    this.series,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    // --- Универсальный парсинг genres ---
    List<String> parsedGenres = [];
    final genresJson = json['genres'];
    if (genresJson is List) {
      parsedGenres = genresJson.map<String>((g) {
        if (g is Map && g['name'] != null) {
          return g['name'].toString();
        }
        return g.toString();
      }).toList();
    }

    // --- Универсальный парсинг series (строка или объект) ---
    String? parsedSeries;
    if (json['series'] is Map && json['series']?['name'] != null) {
      parsedSeries = json['series']?['name'].toString();
    } else if (json['series'] != null) {
      parsedSeries = json['series'].toString();
    }

    return Book(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      reader: json['reader']?.toString(),
      description: json['description']?.toString(),
      coverUrl: json['cover_url']?.toString(),
      thumbUrl: json['thumb_url']?.toString(), // ← миниатюра
      duration: json['duration']?.toString() ?? '',
      genres: parsedGenres,
      series: parsedSeries,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      if (reader != null) 'reader': reader,
      if (description != null) 'description': description,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (thumbUrl != null) 'thumb_url': thumbUrl,
      'duration': duration,
      'genres': genres,
      if (series != null) 'series': series,
    };
  }
}
