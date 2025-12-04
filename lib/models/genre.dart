class Genre {
  final int id;
  final String name;
  final String? imageUrl; // полная URL картинки жанра или null
  final int? booksCount;
  final bool? _hasBooksFlag;

  const Genre({
    required this.id,
    required this.name,
    this.imageUrl,
    this.booksCount,
    bool? hasBooks,
  }) : _hasBooksFlag = hasBooks;

  bool get hasBooks {
    if (_hasBooksFlag != null) return _hasBooksFlag!;
    if (booksCount != null) return booksCount! > 0;
    return true; // якщо API не надіслало лічильник, не приховуємо
  }

  static int? _parseCount(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  /// Створює об'єкт [Genre] з JSON.
  factory Genre.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawCount = json['books_count'] ??
        json['book_count'] ??
        json['abooks_count'] ??
        json['count'] ??
        json['count_books'];
    final hasBooksRaw = json['has_books'] ?? json['hasBooks'];
    bool? hasBooks;
    if (hasBooksRaw is bool) {
      hasBooks = hasBooksRaw;
    } else if (hasBooksRaw is num) {
      hasBooks = hasBooksRaw != 0;
    }

    return Genre(
      id: rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      // бек віддає image_url; на всякий случай поддержим imageUrl
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString(),
      booksCount: _parseCount(rawCount),
      hasBooks: hasBooks,
    );
  }

  /// Перетворює об'єкт [Genre] у JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (imageUrl != null) 'image_url': imageUrl,
    if (booksCount != null) 'books_count': booksCount,
    if (_hasBooksFlag != null) 'has_books': _hasBooksFlag,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Genre && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}