import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants.dart';
import '../models/book.dart';
import '../widgets/favorite_book_card.dart';
import '../widgets/listened_book_card.dart';
import '../widgets/current_listen_card.dart';
import '../user_notifier.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoadingLists = true;
  String? _error;
  List<Book> _favorites = [];
  List<Book> _listened = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchUserLists();
    });
  }

  Future<void> _fetchUserLists() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLists = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        throw Exception('Токен не найден, пользователь не авторизован');
      }

      final url = Uri.parse('$BASE_URL/profile');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final favsData = data['favorites'] as List? ?? [];
        final listenedData = data['listened'] as List? ?? [];
        setState(() {
          _favorites = favsData.map((item) => Book.fromJson(item)).toList();
          _listened = listenedData.map((item) => Book.fromJson(item)).toList();
        });
      } else {
        throw Exception('Ошибка загрузки списков: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLists = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final userNotifier = context.read<UserNotifier>();
    await userNotifier.logout();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userNotifier = context.watch<UserNotifier>();

    if (!userNotifier.isAuth || userNotifier.user == null) {
      return const LoginScreen();
    }

    final user = userNotifier.user!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Личный кабинет'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _fetchUserLists,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildUserInfo(context, user),
          const SizedBox(height: 24),
          const Text(
            'Текущая книга',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const CurrentListenCard(onContinue: null),
          const SizedBox(height: 24),
          _buildSectionTitle('Избранные книги'),
          const SizedBox(height: 8),
          _buildBookList(_favorites, true),
          const SizedBox(height: 24),
          _buildSectionTitle('Прослушанные книги'),
          const SizedBox(height: 8),
          _buildBookList(_listened, false),
          const SizedBox(height: 32),
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildUserInfo(BuildContext context, dynamic user) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(user.email, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Chip(
              label: Text(
                user.isPaid ? 'Подписка активна' : 'Бесплатный доступ',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: user.isPaid ? Colors.green : Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
    );
  }

  Widget _buildBookList(List<Book> books, bool isFavorites) {
    if (_isLoadingLists) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text('Ошибка загрузки: $_error', style: const TextStyle(color: Colors.red));
    }
    if (books.isEmpty) {
      return const Text('Список пуст');
    }

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        itemBuilder: (context, i) {
          final book = books[i];
          // ИСПРАВЛЕНИЕ: убираем coverUrl, так как виджет его больше не принимает
          return isFavorites
              ? FavoriteBookCard(book: book)
              : ListenedBookCard(book: book);
        },
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SafeArea(
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent.withOpacity(0.8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _logout,
          child: const Text('Выйти из аккаунта', style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}
