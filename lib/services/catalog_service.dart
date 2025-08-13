import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants.dart';
import '../models/book.dart';
import '../models/genre.dart';
import '../models/author.dart';

class CatalogService {
  // Загрузка книг с фильтрами (поиском, жанром, автором)
  static Future<List<Book>> fetchBooks({
    String? search,
    Genre? genre,
    Author? author,
  }) async {
    final Map<String, String> params = {};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (genre != null) params['genre'] = genre.name;
    if (author != null) params['author'] = author.name;

    final uri = Uri.parse('$BASE_URL/abooks').replace(queryParameters: params);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data is List ? data : data['data'];
      return items.map((item) => Book.fromJson(item)).toList();
    } else {
      throw Exception('Помилка завантаження: ${response.statusCode}');
    }
  }

  // Загрузка жанров
  static Future<List<Genre>> fetchGenres() async {
    final response = await http.get(Uri.parse('$BASE_URL/genres'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => Genre.fromJson(e)).toList();
    } else {
      throw Exception('Помилка завантаження жанрів');
    }
  }

  // Загрузка авторов
  static Future<List<Author>> fetchAuthors() async {
    final response = await http.get(Uri.parse('$BASE_URL/authors'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => Author.fromJson(e)).toList();
    } else {
      throw Exception('Помилка завантаження авторів');
    }
  }
}
