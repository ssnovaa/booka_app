import 'package:equatable/equatable.dart';
import 'book.dart'; // Импортируем нашу улучшенную модель Book

// Класс наследуется от Equatable для простого и надежного сравнения объектов
class Chapter extends Equatable {
  final int id;
  final String title;
  final int order;
  final String audioUrl;
  final int? duration;
  final Book? book; // Теперь это объект типа Book, а не Map

  // Конструктор теперь const
  const Chapter({
    required this.id,
    required this.title,
    required this.order,
    required this.audioUrl,
    this.duration,
    this.book,
  });

  // Фабричный конструктор для создания экземпляра из JSON
  factory Chapter.fromJson(Map<String, dynamic> json, {Book? book}) {
    // Логику добавления ключей API лучше выносить в слой работы с сетью (например, в Interceptor для http клиента),
    // а не хранить в модели данных.
    String url = json['audio_url']?.toString() ?? '';

    int? chapterDuration;
    if (json['duration'] != null) {
      if (json['duration'] is int) {
        chapterDuration = json['duration'];
      } else if (json['duration'] is String) {
        chapterDuration = int.tryParse(json['duration']);
      }
    }

    // Если явно передали book — используем его.
    // Иначе, если в JSON есть объект 'book', создаем из него экземпляр Book.
    final bookData = book ?? (json['book'] is Map<String, dynamic>
        ? Book.fromJson(json['book'])
        : null);

    return Chapter(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      title: json['title']?.toString() ?? 'Без названия',
      order: json['order'] is int ? json['order'] : int.tryParse(json['order'].toString()) ?? 0,
      audioUrl: url,
      duration: chapterDuration,
      book: bookData,
    );
  }

  // Метод для преобразования экземпляра в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'order': order,
      'audio_url': audioUrl,
      'duration': duration,
      // Если есть объект book, вызываем его собственный toJson
      if (book != null) 'book': book!.toJson(),
    };
  }

  // Equatable автоматически создает `==` и `hashCode` на основе этого списка
  @override
  List<Object?> get props => [id, title, order, audioUrl, duration, book];

  // Геттеры теперь обращаются к свойствам объекта Book, что безопаснее
  String get bookTitle => book?.title ?? 'Без названия';
  String? get coverUrl => book?.displayCoverUrl;
  String? get description => book?.description;
  String? get author => book?.author;
}
