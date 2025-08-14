// lib/services/catalog_service.dart
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart'; // compute
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/genre.dart';
import 'package:booka_app/models/author.dart';

/// Сервис каталога — использует ApiClient (Dio + кэш)
class CatalogService {
  /// Получить список книг с поддержкой per-request кэша и парсингом в isolate.
  ///
  /// Параметры:
  /// - search, genre, author, page, perPage — как обычно
  /// - forceCache: если true — сначала попробуем отдать данные из кэша (CachePolicy.forceCache).
  ///               полезно для мгновенного отображения UI; затем можно вручную вызвать fetchBooks(refresh: true)
  /// - cacheMaxStale: время жизни кэша (по умолчанию 6 часов)
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
        // Парсинг в isolate, чтобы не блокировать главный поток при больших ответах
        final parsed = await compute(_parseBooksPayload, r.data);
        return parsed;
      }

      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    } catch (e) {
      throw AppNetworkException('Parsing error: $e');
    }
  }

  /// Быстрый "refresh" — запрос без использования кэша (обновляет кэш на серверный ответ)
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

  /// Жёсткая проверка/игнор кэша (noCache)
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

      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    } catch (e) {
      throw AppNetworkException('Parsing error: $e');
    }
  }

  /// Получить список жанров (кэшируем дольше — 24 часа)
  static Future<List<Genre>> fetchGenres({Duration? cacheMaxStale}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: CachePolicy.request,
        maxStale: cacheMaxStale ?? const Duration(hours: 24),
      );

      final r = await ApiClient.i().get('/genres', options: cacheOpts.toOptions());

      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is List
            ? data
            : (data is Map && (data['data'] != null || data['items'] != null)
            ? (data['data'] ?? data['items'])
            : []);
        return raw.map((e) => Genre.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }

  /// Получить список авторов (кэш 24 часа)
  static Future<List<Author>> fetchAuthors({Duration? cacheMaxStale}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(
        policy: CachePolicy.request,
        maxStale: cacheMaxStale ?? const Duration(hours: 24),
      );

      final r = await ApiClient.i().get('/authors', options: cacheOpts.toOptions());

      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is List
            ? data
            : (data is Map && (data['data'] != null || data['items'] != null)
            ? (data['data'] ?? data['items'])
            : []);
        return raw.map((e) => Author.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }

  /// Получить одну книгу (кэш по умолчанию request)
  static Future<Book> fetchBook(String id, {Duration? cacheMaxStale}) async {
    try {
      final cacheOpts = ApiClient.cacheOptions(policy: CachePolicy.request, maxStale: cacheMaxStale ?? const Duration(hours: 12));
      final r = await ApiClient.i().get('/books/$id', options: cacheOpts.toOptions());
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        return Book.fromJson(r.data as Map<String, dynamic>);
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }

  /// Удалить кэш конкретного запроса (по пути и query params)
  static Future<void> deleteCacheForBooks({String? search, Genre? genre, Author? author, int page = 1, int perPage = 20}) async {
    final qp = <String, dynamic>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (genre != null) 'genre_id': genre.id,
      if (author != null) 'author_id': author.id,
      'page': page,
      'per_page': perPage,
    };
    await ApiClient.deleteCacheFor('/books', queryParameters: qp);
  }

  /// Очистить весь кэш каталога (весь store)
  static Future<void> clearAllCache() async {
    await ApiClient.clearAllCache();
  }
}

/// PARSING UTIL — вызывается в isolate (compute)
List<Book> _parseBooksPayload(dynamic raw) {
  final List<dynamic> items;
  if (raw is List) {
    items = raw;
  } else if (raw is Map<String, dynamic>) {
    items = (raw['items'] ?? raw['data'] ?? raw['books'] ?? []);
  } else {
    items = [];
  }
  return items.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
}
