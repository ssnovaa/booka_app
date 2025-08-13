import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

// --- Services ---

// Сервис для взаимодействия с API.
// В реальном приложении здесь будет логика запросов к API.
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

// --- Providers ---

// Провайдер для управления состоянием аутентификации
class AuthProvider with ChangeNotifier {
  String? _authToken;
  bool _isLoading = false;

  String? get authToken => _authToken;
  bool get isAuthenticated => _authToken != null;
  bool get isLoading => _isLoading;

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Имитация запроса к API для входа
      await Future.delayed(const Duration(seconds: 1));
      // В реальном приложении здесь будет логика получения токена
      _authToken = 'mock-auth-token-12345';
    } catch (e) {
      print('Ошибка входа: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    _authToken = null;
    notifyListeners();
  }
}

// Провайдер для управления состоянием списка книг
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


// --- Widgets ---

// Главный виджет приложения, использующий провайдеры
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Используем `MultiProvider` для предоставления нескольких провайдеров
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // `ProxyProvider` позволяет создать BooksProvider, который зависит от AuthProvider
        ProxyProvider<AuthProvider, BooksProvider>(
          update: (_, auth, __) => BooksProvider(ApiService(auth.authToken)),
        ),
      ],
      child: MaterialApp(
        title: 'Booka App (Refactoring)',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            // В зависимости от состояния аутентификации показываем разные экраны
            if (auth.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return auth.isAuthenticated ? const BooksScreen() : const LoginScreen();
          },
        ),
      ),
    );
  }
}

// Экран входа
class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Вызываем метод входа из провайдера
            context.read<AuthProvider>().login('user', 'password');
          },
          child: const Text('Войти'),
        ),
      ),
    );
  }
}

// Экран со списком книг
class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  _BooksScreenState createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  @override
  void initState() {
    super.initState();
    // Запрашиваем книги при инициализации экрана
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BooksProvider>().fetchBooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Книги'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Выход из системы
              context.read<AuthProvider>().logout();
            },
          )
        ],
      ),
      body: Consumer<BooksProvider>(
        builder: (context, booksProvider, child) {
          if (booksProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (booksProvider.books.isEmpty) {
            return const Center(child: Text('Книг нет'));
          }
          return ListView.builder(
            itemCount: booksProvider.books.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(booksProvider.books[index]),
              );
            },
          );
        },
      ),
    );
  }
}

// Основная функция для запуска приложения
void main() {
  runApp(App());
}
