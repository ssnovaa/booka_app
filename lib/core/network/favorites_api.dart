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
// 1️⃣ Імпортуємо репозиторій профілю для сповіщень
import 'package:booka_app/repositories/profile_repository.dart';

class FavoritesApi {
  FavoritesApi._();
  static Dio get _dio => ApiClient.i();

  /// Додати книгу у вибране.
  static Future<void> add(int bookId) async {
    await _dio.post('/favorites/$bookId');

    // 🔴 ЗМІНА: Оновлюємо локальний кеш замість його видалення (invalidate).
    // Це дозволяє миттєво відобразити зміни на головному екрані, оскільки кеш залишається доступним.
    ProfileRepository.I.updateLocalFavorites(bookId, true);
  }

  /// Прибрати книгу з вибраного.
  static Future<void> remove(int bookId) async {
    await _dio.delete('/favorites/$bookId');

    // 🔴 ЗМІНА: Видаляємо конкретну книгу з локального кешу.
    ProfileRepository.I.updateLocalFavorites(bookId, false);
  }
}