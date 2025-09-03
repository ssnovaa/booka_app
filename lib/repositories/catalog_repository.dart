// lib/repositories/catalog_repository.dart
import 'package:flutter/foundation.dart' show compute;
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/author.dart';
import 'package:booka_app/models/genre.dart';
import 'package:booka_app/core/network/json_parsers.dart';

class CatalogRepository {
  const CatalogRepository();

  /// Получить книги: парсинг в отдельном изоляте.
  Future<List<Book>> fetchBooks({Map<String, dynamic>? query}) async {
    final resp = await ApiClient.i().get(
      '/abooks',
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,             // ← важное изменение
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) return const <Book>[];
    // resp.data — String, поэтому compute можно безопасно использовать
    return compute(parseBooksFromString, resp.data as String);
  }

  Future<List<Author>> fetchAuthors({Map<String, dynamic>? query}) async {
    final resp = await ApiClient.i().get(
      '/authors',
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) return const <Author>[];
    return compute(parseAuthorsFromString, resp.data as String);
  }

  Future<List<Genre>> fetchGenres({Map<String, dynamic>? query}) async {
    final resp = await ApiClient.i().get(
      '/genres',
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) return const <Genre>[];
    return compute(parseGenresFromString, resp.data as String);
  }
}
