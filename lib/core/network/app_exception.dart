// lib/core/network/app_exception.dart

/// Універсальне виключення для мережевих помилок у застосунку.
/// Додає повідомлення та, за потреби, HTTP статус-код відповіді.
class AppNetworkException implements Exception {
  final String message;
  final int? statusCode;

  AppNetworkException(this.message, {this.statusCode});

  @override
  String toString() => 'AppNetworkException($statusCode): $message';
}
