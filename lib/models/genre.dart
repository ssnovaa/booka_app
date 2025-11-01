class Genre {
  final int id;
  final String name;
  final String? imageUrl; // полная URL картинки жанра или null

  const Genre({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  /// Створює об'єкт [Genre] з JSON.
  factory Genre.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return Genre(
      id: rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      // бек віддає image_url; на всякий случай поддержим imageUrl
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString(),
    );
  }

  /// Перетворює об'єкт [Genre] у JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (imageUrl != null) 'image_url': imageUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Genre && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
