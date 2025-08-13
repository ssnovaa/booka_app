import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:booka_app/api_service.dart';
import 'package:booka_app/auth_provider.dart';
import 'package:booka_app/books_provider.dart';

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
