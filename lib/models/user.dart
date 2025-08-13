class User {
  final int id;
  final String name;
  final String email;
  final bool isPaid;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.isPaid,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      isPaid: json['is_paid'] ?? false,
    );
  }
}
enum UserType { guest, free, paid }

UserType getUserType(User? user) {
  if (user == null) return UserType.guest;
  return user.isPaid ? UserType.paid : UserType.free;
}
