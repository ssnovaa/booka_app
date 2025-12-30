// ШЛЯХ: lib/models/book.dart

import '../constants.dart'; // 👈 Додано імпорт констант

/// Модель аудіокниги без скорочень.
class Book {
  final int id;
  final String title;
  final String author;
  final String? reader;
  final String? description;

  /// Повний URL обкладинки (може бути відсутній).
  final String? coverUrl;

  /// Мініатюра (може бути відсутня).
  final String? thumbUrl;

  /// Тривалість завжди зберігаємо як рядок.
  final String duration;

  /// Жанри як список рядків.
  final List<String> genres;

  /// Назва серії.
  final String? series;

  /// Числовий ідентифікатор серії.
  final int? seriesId;

  /// Швидка ознака: чи використовується мініатюра.
  bool get isThumbUsed => (thumbUrl ?? '').trim().isNotEmpty;

  /// Єдина точка доступу до зображення: повертає оброблене абсолютне посилання.
  /// 🔥 ВИПРАВЛЕНО: Тепер використовує ensureAbsoluteImageUrl для сумісності з R2.
  String get displayCoverUrl {
    final t = (thumbUrl ?? '').trim();
    final c = (coverUrl ?? '').trim();
    final target = t.isNotEmpty ? t : c;

    // Якщо target порожній, повертаємо порожній рядок, інакше оброблене посилання
    return ensureAbsoluteImageUrl(target) ?? '';
  }

  /// Чи є будь-яка інформація про серію.
  bool get hasSeries =>
      (seriesId != null) || ((series ?? '').trim().isNotEmpty);

  const Book({
    required this.id,
    required this.title,
    required this.author,
    this.reader,
    this.description,
    this.coverUrl,
    this.thumbUrl,
    required this.duration,
    this.genres = const <String>[],
    this.series,
    this.seriesId,
  });

  /// Універсальний парсер int.
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  /// Акуратне діставання текстової назви серії з різних форматів.
  static String? _parseSeriesText(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final s = raw.trim();
      return s.isEmpty ? null : s;
    }
    if (raw is Map) {
      final t = raw['title'] ?? raw['name'];
      if (t is String) {
        final s = t.trim();
        return s.isEmpty ? null : s;
      }
    }
    final s = raw.toString().trim();
    if (s.isEmpty || s == '{}' || s == '[]') return null;
    return s;
  }

  /// Універсальний парсинг жанрів у список рядків.
  static List<String> _parseGenres(dynamic raw) {
    final out = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String) {
          final s = e.trim();
          if (s.isNotEmpty) out.add(s);
        } else if (e is Map) {
          final n = e['name'];
          if (n is String && n.trim().isNotEmpty) {
            out.add(n.trim());
          } else {
            final s = e.toString().trim();
            if (s.isNotEmpty && s != '{}' && s != '[]') out.add(s);
          }
        } else {
          final s = e.toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
      }
    }
    return out;
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    final dynamic rawSeriesId =
        json['series_id'] ??
            json['seriesId'] ??
            (json['series'] is Map ? (json['series']['id']) : null);

    return Book(
      id: _toInt(json['id']) ?? 0,
      title: (json['title']?.toString() ?? '').trim(),
      author: (json['author']?.toString() ?? '').trim(),
      reader: (json['reader']?.toString()).let((s) => s?.trim().isEmpty == true ? null : s?.trim()),
      description: (json['description']?.toString()).let((s) => s?.trim().isEmpty == true ? null : s?.trim()),
      coverUrl: (json['cover_url']?.toString()).let((s) => s?.trim().isEmpty == true ? null : s?.trim()),
      thumbUrl: (json['thumb_url']?.toString()).let((s) => s?.trim().isEmpty == true ? null : s?.trim()),
      duration: (json['duration']?.toString() ?? '').trim(),
      genres: _parseGenres(json['genres']),
      series: _parseSeriesText(json['series']),
      seriesId: _toInt(rawSeriesId),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'author': author,
      if ((reader ?? '').toString().trim().isNotEmpty) 'reader': reader,
      if ((description ?? '').toString().trim().isNotEmpty) 'description': description,
      if ((coverUrl ?? '').toString().trim().isNotEmpty) 'cover_url': coverUrl,
      if ((thumbUrl ?? '').toString().trim().isNotEmpty) 'thumb_url': thumbUrl,
      'duration': duration,
      'genres': genres,
      if ((series ?? '').toString().trim().isNotEmpty) 'series': series,
      if (seriesId != null) 'series_id': seriesId,
    };
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}