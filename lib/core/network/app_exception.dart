// lib/core/network/app_exception.dart
class AppNetworkException implements Exception {
  final String message;
  final int? statusCode;
  AppNetworkException(this.message, {this.statusCode});
  @override
  String toString() => 'AppNetworkException($statusCode): $message';
}
