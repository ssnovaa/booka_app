class Genre {
  final int id;
  final String name;

  Genre({required this.id, required this.name});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Genre && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
