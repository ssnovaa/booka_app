// lib/core/security/safe_errors.dart
import 'package:dio/dio.dart';

String safeErrorMessage(Object error) {
  // По умолчанию — нейтральное сообщение
  const generic = 'Щось пішло не так. Перевірте зʼєднання або спробуйте ще раз.';

  // Dio: не показываем URL, заголовки и прочее
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code != null) {
      // Мягкие, человеко-понятные тексты по коду
      if (code == 401) return 'Потрібна повторна авторизація.';
      if (code == 403) return 'Недостатньо прав для цієї дії.';
      if (code == 404) return 'Ресурс не знайдено.';
      if (code >= 500) return 'Сервер тимчасово недоступний.';
    }
    return generic;
  }

  // Любые другие — без деталей
  return generic;
}
