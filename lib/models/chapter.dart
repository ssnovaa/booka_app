class Chapter {
  final int id;
  final String title;
  final int order;
  final String audioUrl;
  final int? duration;
  final Map<String, dynamic>? book; // Вся информация о книге (название, обложка и т.д.)

  Chapter({
    required this.id,
    required this.title,
    required this.order,
    required this.audioUrl,
    this.duration,
    this.book,
  });

  /// Универсальный fromJson — book можно передать отдельно (или взять из json, если есть)
  factory Chapter.fromJson(Map<String, dynamic> json, {Map<String, dynamic>? book}) {
    String url = json['audio_url'] ?? '';

    int? chapterDuration;
    if (json['duration'] != null) {
      if (json['duration'] is int) {
        chapterDuration = json['duration'];
      } else if (json['duration'] is String) {
        chapterDuration = int.tryParse(json['duration']);
      }
    }

    // Если явно передали book — используем, иначе ищем в json['book'] (универсальность)
    final bookData = book ?? (json['book'] is Map<String, dynamic> ? json['book'] : null);

    return Chapter(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      title: json['title']?.toString() ?? '',
      order: json['order'] is int ? json['order'] : int.tryParse(json['order'].toString()) ?? 0,
      audioUrl: url,
      duration: chapterDuration,
      book: bookData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'order': order,
      'audio_url': audioUrl,
      'duration': duration,
      if (book != null) 'book': book,
    };
  }

  /// Удобные геттеры для UI:
  String get bookTitle => (book?['title'] ?? '') as String;
  String? get coverUrl => book?['cover_url'] as String?;
  String? get description => book?['description'] as String?;
  String? get author => book?['author'] as String?;
}
