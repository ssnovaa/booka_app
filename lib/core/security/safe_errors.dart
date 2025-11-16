import 'dart:async'; // TimeoutException
import 'dart:io';    // SocketException (OK для iOS/Android)
import 'package:dio/dio.dart';

/// Безопасное пользовательское сообщение по ошибке.
/// НИКОГДА не включает URL, IP, хосты и сырые сообщения сервера.
String safeErrorMessage(
    Object error, {
      String? fallback,
    }) {
  final fb = fallback ?? 'Сталася помилка. Спробуйте ще раз.';

  try {
    if (error is DioException) {
      final sc = error.response?.statusCode;

      // Сетевые таймауты/ошибки соединения
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Тайм-аут зʼєднання. Перевірте інтернет.';
        case DioExceptionType.connectionError:
          if (error.error is SocketException) {
            return 'Немає зʼєднання з сервером. Перевірте інтернет.';
          }
          break;
        case DioExceptionType.badCertificate:
          return 'Помилка безпеки зʼєднання.';
        case DioExceptionType.cancel:
        case DioExceptionType.badResponse:
        case DioExceptionType.unknown:
          break;
      }

      // Код HTTP, без деталей
      if (sc != null) {
        if (sc == 401) return 'Невірні облікові дані або їх строк минув.';
        if (sc == 403) return 'Доступ заборонено.';
        if (sc == 404) return 'Ресурс не знайдено.';
        if (sc == 408) return 'Тайм-аут запиту. Спробуйте ще раз.';
        if (sc == 429) return 'Забагато запитів. Спробуйте пізніше.';
        if (sc >= 500) return 'Проблема на сервері. Спробуйте пізніше.';
      }

      return fb;
    }

    if (error is SocketException) {
      return 'Немає зʼєднання з сервером. Перевірте інтернет.';
    }
    if (error is TimeoutException) {
      return 'Тайм-аут операції. Спробуйте ще раз.';
    }
    if (error is FormatException) {
      return 'Неправильний формат даних.';
    }

    return fb;
  } catch (_) {
    return fb;
  }
}

/// Безопасно дописывает HTTP-код к базовому сообщению.
/// Не раскрывает URL/хост/текст ответа сервера.
String safeHttpStatus(String base, int? statusCode) {
  if (statusCode == null || statusCode <= 0) return base;
  return '$base (код $statusCode)';
}

/// Для логов (НЕ для UI). Обрезает длинные сообщения.
String safeLogString(Object? error) {
  if (error == null) return 'unknown';
  final s = error.toString();
  return s.length > 500 ? s.substring(0, 500) : s;
}
