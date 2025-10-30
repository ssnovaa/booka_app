
// ШЛЯХ: lib/core/network/favorites_api.dart
//
// Мінімальний клієнт для «Вибране»:
// - додати книгу у вибране: POST /favorites/{id}
// - (за потреби) видалити з вибраного: DELETE /favorites/{id}
// БЕЗ провайдерів стану; просто мережеві виклики.
//
// Усі коментарі — українською.

import 'package:dio/dio.dart';
import 'package:booka_app/core/network/api_client.dart';

class FavoritesApi {
  FavoritesApi._();
  static Dio get _dio => ApiClient.i();

  /// Додати книгу у вибране.
  static Future<void> add(int bookId) async {
    await _dio.post('/favorites/$bookId');
  }

  /// Прибрати книгу з вибраного (не використовується в мінімальному сценарії).
  static Future<void> remove(int bookId) async {
    await _dio.delete('/favorites/$bookId');
  }
}
