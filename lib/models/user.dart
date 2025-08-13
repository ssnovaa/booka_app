import 'package:equatable/equatable.dart';

// Enum для удобного определения типа пользователя
enum UserType { guest, free, paid }

// Класс наследуется от Equatable для простого и надежного сравнения объектов
class User extends Equatable {
  final int id;
  final String name;
  final String email;
  final bool isPaid;

  // Конструктор теперь const
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.isPaid,
  });

  // Фабричный конструктор для создания экземпляра из JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? 'Пользователь',
      email: json['email']?.toString() ?? '',
      // Обеспечиваем корректную обработку булевых значений
      isPaid: json['is_paid'] == true || json['is_paid'] == 1,
    );
  }

  // Метод для преобразования экземпляра в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'is_paid': isPaid,
    };
  }

  // Equatable автоматически создает `==` и `hashCode` на основе этого списка
  @override
  List<Object?> get props => [id, name, email, isPaid];
}

// Вспомогательная функция для определения типа пользователя.
// Ее удобно держать в этом же файле.
UserType getUserType(User? user) {
  if (user == null) return UserType.guest;
  return user.isPaid ? UserType.paid : UserType.free;
}
