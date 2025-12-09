// lib/services/catalog_service.dart
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart'; // compute
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/genre.dart';
import 'package:booka_app/models/author.dart';
// ⛑ Безпечні тексти помилок (санітизація)
import 'package:booka_app/core/security/safe_errors.dart';

/// Сервіс каталогу — використовує ApiClient (Dio + кеш).
class CatalogService {
  /// Отримати список книг з підтримкою per-request кешу та парсингом в isolate.
  static Future<List<Book>> fetchBooks({
    String? search,
    Genre? genre,
    Author? author,
    int page = 1,
    int perPage = 20,
    bool forceCache = false,
    Duration? cacheMaxStale,
  }) async {
    try {
      final dio = ApiClient.i();
      final qp = <String, dynamic>{
        if (search != null && search.isNotEmpty) 'search': search,
        if (genre != null) 'genre_id': genre.id,
        if (author != null) 'author_id': author.id,
        'page': page,
        'per_page': perPage,
      };

      final cacheOpts = ApiClient.cacheOptions(
        policy: forceCache ? CachePolicy.forceCache : CachePolicy.request,
        maxStale: cacheMaxStale ?? const Duration(hours: 6),
      );

      final Response r = await dio.get(
        '/books',
        queryParameters: qp,
        options: cacheOpts.toOptions(),
      );

      if (r.statusCode == 200) {
        final parsed = await compute(_parseBooksPayload, r.data);
        return parsed;
      }

      throw AppNetworkException(
        'Непередбачувана відповідь',
        statusCode: r.statusCode,
      );
    } on DioException catch (e) {
      throw AppNetworkException(
        safeErrorMessage(e, fallback: 'Мережева помилка'),
        statusCode: e.response?.statusCode,
      );
    } catch (_) {
      throw AppNetworkException('Помилка парсингу даних');
    }
  }

  /// Швидкий "refresh" — запит без використання кеша
  static Future<List<Book>> fetchBooksRefresh({
    String? search,
    Genre? genre,
    Author? author,
    int page = 1,
    int perPage = 20,
  }) =>
      fetchBooks(
        search: search,
        genre: genre,
        author: author,
        page: page,
        perPage: perPage,
        forceCache: false,
        cacheMaxStale: const Duration(hours: 0),
      );

  /// Жорстке ігнорування кеша (noCache)
  static Future<List<Book>> fetchBooksNoCache({
    String? search,
    Genre? genre,
    Author? author,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final dio = ApiClient.i();
      final qp = <String, dynamic>{
        if (search != null && search.isNotEmpty) 'search': search,
        if (genre != null) 'genre_id': genre.id,
        if (author != null) 'author_id': author.id,
        'page': page,
        'per_page': perPage,
      };

      final cacheOpts = ApiClient.cacheOptions(
        policy: CachePolicy.noCache,
        maxStale: const Duration(seconds: 0),
      );

      final Response r = await dio.get(
        '/books',
        queryParameters: qp,
        options: cacheOpts.toOptions(),
      );

      if (r.statusCode == 200) {
        final parsed = await compute(_parseBooksPayload, r.data);
        return parsed;
      }

      throw AppNetworkException(
        'Непередбачувана відповідь',
        statusCode: r.statusCode,
      );
    } on DioException catch (e) {
      throw AppNetworkException(
        safeErrorMessage(e, fallback: 'Мережева помилка'),
        statusCode: e.response?.statusCode,
      );
    } catch (_) {
      throw AppNetworkException('Помилка парсингу даних');
    }
  }

  /// Отримати список жанрів (кешуємо довше — 24 години)
  static Future<List<Genre>> fetchGenres({Duration? cacheMaxStale}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: CachePolicy.request,
        maxStale: cacheMaxStale ?? const Duration(hours: 24),
      );

      final r =
      await ApiClient.i().get('/genres', options: cacheOpts.toOptions());

      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is List
            ? data
            : (data is Map &&
            (data['data'] != null || data['items'] != null)
            ? (data['data'] ?? data['items'])
            : []);
        return raw
            .map((e) => Genre.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      throw AppNetworkException(
        'Непередбачувана відповідь',
        statusCode: r.statusCode,
      );
    } on DioException catch (e) {
      throw AppNetworkException(
        safeErrorMessage(e, fallback: 'Мережева помилка'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Отримати список авторів (кеш 24 години)
  static Future<List<Author>> fetchAuthors({Duration? cacheMaxStale}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: CachePolicy.request,
        maxStale: cacheMaxStale ?? const Duration(hours: 24),
      );

      final r =
      await ApiClient.i().get('/authors', options: cacheOpts.toOptions());

      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is List
            ? data
            : (data is Map &&
            (data['data'] != null || data['items'] != null)
            ? (data['data'] ?? data['items'])
            : []);
        return raw
            .map((e) => Author.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      throw AppNetworkException(
        'Непередбачувана відповідь',
        statusCode: r.statusCode,
      );
    } on DioException catch (e) {
      throw AppNetworkException(
        safeErrorMessage(e, fallback: 'Мережева помилка'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Отримати одну книгу (кеш за замовчуванням request)
  static Future<Book> fetchBook(String id, {Duration? cacheMaxStale}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: CachePolicy.request,
        maxStale: cacheMaxStale ?? const Duration(hours: 12),
      );
      final r = await ApiClient.i()
          .get('/books/$id', options: cacheOpts.toOptions());

      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        return Book.fromJson(r.data as Map<String, dynamic>);
      }

      throw AppNetworkException(
        'Непередбачувана відповідь',
        statusCode: r.statusCode,
      );
    } on DioException catch (e) {
      throw AppNetworkException(
        safeErrorMessage(e, fallback: 'Мережева помилка'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Видалити кеш для конкретного запиту (шлях + query params)
  static Future<void> deleteCacheForBooks({
    String? search,
    Genre? genre,
    Author? author,
    int page = 1,
    int perPage = 20,
  }) async {
    final qp = <String, dynamic>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (genre != null) 'genre_id': genre.id,
      if (author != null) 'author_id': author.id,
      'page': page,
      'per_page': perPage,
    };
    await ApiClient.deleteCacheFor('/books', queryParameters: qp);
  }

  /// Очистити увесь кеш каталогу (весь store)
  static Future<void> clearAllCache() async {
    await ApiClient.clearAllCache();
  }

  // --- 🆕 МЕТОДИ ДЛЯ СЕРІЙ КНИГ (З КЕШУВАННЯМ) ---

  /// Отримати список усіх серій (кеш 12 годин)
  static Future<List<Map<String, dynamic>>> fetchSeries({bool forceRefresh = false}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: forceRefresh ? CachePolicy.refreshForceCache : CachePolicy.request,
        maxStale: const Duration(hours: 12),
      );

      final r = await ApiClient.i().get(
        '/series',
        options: cacheOpts.toOptions(),
      );

      if (r.statusCode == 200) {
        final data = r.data;
        // Логіка розбору, аналогічна тій, що була в UI
        final raw = (data is Map && (data as Map).containsKey('data'))
            ? (data['data'] as List?)
            : (data is List ? data as List : null);

        if (raw == null) return [];

        return raw
            .whereType<dynamic>()
            .map((e) => e is Map<String, dynamic>
            ? e
            : Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Отримати книги конкретної серії (кеш 6 годин)
  static Future<List<Map<String, dynamic>>> fetchSeriesBooks(
      String seriesId, {
        bool forceRefresh = false,
      }) async {
    final cacheOpts = ApiClient.cacheOptions(
      policy: forceRefresh ? CachePolicy.refreshForceCache : CachePolicy.request,
      maxStale: const Duration(hours: 6),
    );

    // Спроба 1: прямий ендпоінт
    try {
      final r = await ApiClient.i().get(
        '/series/$seriesId/books',
        options: cacheOpts.toOptions(),
      );
      if (r.statusCode == 200 && r.data is List) {
        return (r.data as List)
            .map((e) => e is Map<String, dynamic>
            ? e
            : Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}

    // Спроба 2: фільтр через abooks (fallback)
    try {
      final r = await ApiClient.i().get(
        '/abooks',
        queryParameters: {'series': seriesId},
        options: cacheOpts.toOptions(),
      );
      if (r.statusCode == 200) {
        final data = r.data;
        if (data is Map && data['data'] is List) {
          return (data['data'] as List)
              .map((e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map))
              .toList();
        } else if (data is List) {
          return (data as List)
              .map((e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (_) {}

    return [];
  }
}

/// PARSING UTIL — викликається в isolate (compute)
List<Book> _parseBooksPayload(dynamic raw) {
  final List<dynamic> items;
  if (raw is List) {
    items = raw;
  } else if (raw is Map<String, dynamic>) {
    items = (raw['items'] ?? raw['data'] ?? raw['books'] ?? []);
  } else {
    items = [];
  }
  return items
      .map((e) => Book.fromJson(e as Map<String, dynamic>))
      .toList();
}