// lib/models/user.dart

/// Тип користувача для UI-логіки.
enum UserType { guest, free, paid }

class User {
  final int id;
  final String name;
  final String email;

  /// Прямой флаг с бэка: если true — пользователь платный безусловно.
  final bool isPaid;

  /// Дедлайн платного статуса: если в будущем — считаем платным даже офлайн.
  /// Може бути null, якщо підписки немає.
  final DateTime? paidUntil;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.isPaid,
    required this.paidUntil,
  });

  /// Истинный статус платности «на сейчас».
  /// Если paidUntil в будущем — возвращает true, иначе — смотрит на isPaid.
  bool get isPaidNow {
    if (isPaid == true) return true;
    if (paidUntil == null) return false;
    final nowUtc = DateTime.now().toUtc();
    return paidUntil!.toUtc().isAfter(nowUtc);
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final rawPaidUntil = json['paid_until'];
    DateTime? parsedPaidUntil;

    if (rawPaidUntil is String && rawPaidUntil.isNotEmpty) {
      parsedPaidUntil = DateTime.tryParse(rawPaidUntil);
    } else if (rawPaidUntil is DateTime) {
      parsedPaidUntil = rawPaidUntil;
    } else {
      parsedPaidUntil = null;
    }

    return User(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      isPaid: (json['is_paid'] ?? false) as bool,
      paidUntil: parsedPaidUntil,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'is_paid': isPaid,
      'paid_until': paidUntil?.toIso8601String(),
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? email,
    bool? isPaid,
    DateTime? paidUntil,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      isPaid: isPaid ?? this.isPaid,
      paidUntil: paidUntil ?? this.paidUntil,
    );
  }
}

/// Універсальна утиліта для UI:
/// null → guest; isPaidNow → paid; інакше → free.
UserType getUserType(User? user) {
  if (user == null) return UserType.guest;
  return user.isPaidNow ? UserType.paid : UserType.free;
}
