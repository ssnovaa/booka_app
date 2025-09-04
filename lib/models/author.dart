class Author {
  final int id;
  final String name;

  Author({required this.id, required this.name});

  /// Створює об'єкт [Author] з JSON.
  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}
