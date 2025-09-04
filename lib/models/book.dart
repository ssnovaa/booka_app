// ШЛЯХ: lib/models/book.dart

class Book {
  final int id;
  final String title;
  final String author;
  final String? reader;
  final String? description;

  /// Повний URL обкладинки (може бути відсутній).
  final String? coverUrl;

  /// Мініатюра (може бути відсутня). Якщо є — використовуємо її в картках.
  final String? thumbUrl;

  /// ВАЖЛИВО: duration завжди приходить як String (залишаємо так).
  final String duration;

  /// Жанри приводимо до List<String>.
  final List<String> genres;

  final String? series;

  /// Швидка ознака: чи використовується мініатюра.
  bool get isThumbUsed => (thumbUrl ?? '').trim().isNotEmpty;

  /// Єдина точка доступу до зображення: повертає thumbUrl, якщо є,
  /// інакше coverUrl, інакше порожній рядок.
  String get displayCoverUrl {
    final t = (thumbUrl ?? '').trim();
    if (t.isNotEmpty) return t;

    final c = (coverUrl ?? '').trim();
    if (c.isNotEmpty) return c;

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
    // --- Універсальний парсинг genres ---
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

    // --- Універсальний парсинг series (рядок або обʼєкт) ---
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
      thumbUrl: json['thumb_url']?.toString(), // ← мініатюра
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
