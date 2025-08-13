// lib/catalog_service.dart
import 'package:dio/dio.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/genre.dart';
import 'package:booka_app/models/author.dart';

class CatalogService {
  static Future<List<Book>> fetchBooks({
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

      final Response r = await dio.get('/books', queryParameters: qp);
      if (r.statusCode == 200) {
        final data = r.data;
        final List raw = data is Map<String, dynamic> ? (data['items'] ?? data['data'] ?? []) : (data as List);
        return raw.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }

  static Future<List<Genre>> fetchGenres() async {
    try {
      final r = await ApiClient.i().get('/genres');
      if (r.statusCode == 200) {
        final List raw = r.data is List ? r.data : (r.data['items'] ?? []);
        return raw.map((e) => Genre.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }

  static Future<List<Author>> fetchAuthors() async {
    try {
      final r = await ApiClient.i().get('/authors');
      if (r.statusCode == 200) {
        final List raw = r.data is List ? r.data : (r.data['items'] ?? []);
        return raw.map((e) => Author.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }

  static Future<Book> fetchBook(String id) async {
    try {
      final r = await ApiClient.i().get('/books/$id');
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        return Book.fromJson(r.data as Map<String, dynamic>);
      }
      throw AppNetworkException('Unexpected response', statusCode: r.statusCode);
    } on DioException catch (e) {
      throw AppNetworkException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
    }
  }
}
