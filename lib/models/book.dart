import 'package:equatable/equatable.dart'; // Для сравнения объектов

// Класс наследуется от Equatable для простого и надежного сравнения объектов
class Book extends Equatable {
  final int id;
  final String title;
  final String author;
  final String? reader;
  final String? description;
  final String? coverUrl;
  final String? thumbUrl;
  final String duration;
  final List<String> genres;
  final String? series;

  // Конструктор теперь const
  const Book({
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

  /// Единая точка доступа к изображению:
  /// отдает thumbUrl, если есть, иначе coverUrl.
  String? get displayCoverUrl {
    if (thumbUrl != null && thumbUrl!.trim().isNotEmpty) {
      return thumbUrl;
    }
    if (coverUrl != null && coverUrl!.trim().isNotEmpty) {
      return coverUrl;
    }
    return null; // Возвращаем null, если изображений нет
  }

  // Фабричный конструктор для создания экземпляра из JSON
  factory Book.fromJson(Map<String, dynamic> json) {
    // --- Универсальный парсинг genres ---
    List<String> parsedGenres = [];
    final genresJson = json['genres'];
    if (genresJson is List) {
      parsedGenres = genresJson.map<String>((g) {
        if (g is Map && g.containsKey('name')) {
          return g['name'].toString();
        }
        return g.toString();
      }).toList();
    }

    // --- Универсальный парсинг series (строка или объект) ---
    String? parsedSeries;
    if (json['series'] is Map && json['series']?['name'] != null) {
      parsedSeries = json['series']['name'].toString();
    } else if (json['series'] != null) {
      parsedSeries = json['series'].toString();
    }

    return Book(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      title: json['title']?.toString() ?? 'Без названия',
      author: json['author']?.toString() ?? 'Неизвестный автор',
      reader: json['reader']?.toString(),
      description: json['description']?.toString(),
      coverUrl: json['cover_url']?.toString(),
      thumbUrl: json['thumb_url']?.toString(),
      duration: json['duration']?.toString() ?? '',
      genres: parsedGenres,
      series: parsedSeries,
    );
  }

  // Метод для преобразования экземпляра в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'reader': reader,
      'description': description,
      'cover_url': coverUrl,
      'thumb_url': thumbUrl,
      'duration': duration,
      'genres': genres,
      'series': series,
    };
  }

  // Equatable автоматически создает `==` и `hashCode` на основе этого списка
  @override
  List<Object?> get props => [
    id,
    title,
    author,
    reader,
    description,
    coverUrl,
    thumbUrl,
    duration,
    genres,
    series,
  ];
}
