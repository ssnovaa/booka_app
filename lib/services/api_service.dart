import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000/api'));

  ApiService(String? authToken) {
    if (authToken != null) {
      _dio.options.headers['Authorization'] = 'Token $authToken';
    }
  }

  Future<List<String>> fetchBooks() async {
    // Имитация задержки сети и запроса к API
    await Future.delayed(const Duration(seconds: 2));
    final response = await _dio.get('/books');
    // В реальном приложении здесь будет обработка ответа
    return ['Книга 1', 'Книга 2', 'Книга 3'];
  }
}
