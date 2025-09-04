class Chapter {
  final int id;
  final String title;
  final int order;
  final String audioUrl;
  final int? duration;
  final Map<String, dynamic>? book; // Вся інформація про книгу (назва, обкладинка тощо)

  Chapter({
    required this.id,
    required this.title,
    required this.order,
    required this.audioUrl,
    this.duration,
    this.book,
  });

  /// Універсальний fromJson — [book] можна передати окремо (або взяти з json, якщо є).
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

    // Якщо явно передали [book] — використовуємо його, інакше шукаємо в json['book'] (універсальність).
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

  /// Перетворює [Chapter] у JSON.
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

  /// Зручні гетери для UI:
  String get bookTitle => (book?['title'] ?? '') as String;
  String? get coverUrl => book?['cover_url'] as String?;
  String? get description => book?['description'] as String?;
  String? get author => book?['author'] as String?;
}
