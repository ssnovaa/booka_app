import 'package:flutter/material.dart';
import 'package:booka_app/api_service.dart'; // Предполагаемый импорт

class BooksProvider with ChangeNotifier {
  final ApiService _apiService;
  List<String> _books = [];
  bool _isLoading = false;

  BooksProvider(this._apiService);

  List<String> get books => _books;
  bool get isLoading => _isLoading;

  Future<void> fetchBooks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _books = await _apiService.fetchBooks();
    } catch (e) {
      print('Ошибка получения книг: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
