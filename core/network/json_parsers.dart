// lib/core/network/json_parsers.dart
import 'dart:convert';

import 'package:booka_app/models/book.dart';
import 'package:booka_app/models/author.dart';
import 'package:booka_app/models/genre.dart';

/// Універсальна функція: дістає List<Map> як із {[data]: [...]} так і з просто [...]
List<Map<String, dynamic>> _extractList(dynamic root) {
  if (root is List) {
    return root.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (root is Map<String, dynamic>) {
    final data = root['data'];
    if (data is List) {
      return data.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
  }
  return const <Map<String, dynamic>>[];
}

/// ======== BOOKS (КНИГИ) ========
List<Book> parseBooksFromString(String body) {
  final dynamic decoded = jsonDecode(body);
  final list = _extractList(decoded);
  return list.map((m) => Book.fromJson(m)).toList();
}

/// ======== AUTHORS (АВТОРИ) ========
List<Author> parseAuthorsFromString(String body) {
  final dynamic decoded = jsonDecode(body);
  final list = _extractList(decoded);
  return list.map((m) => Author.fromJson(m)).toList();
}

/// ======== GENRES (ЖАНРИ) ========
List<Genre> parseGenresFromString(String body) {
  final dynamic decoded = jsonDecode(body);
  final list = _extractList(decoded);
  return list.map((m) => Genre.fromJson(m)).toList();
}
