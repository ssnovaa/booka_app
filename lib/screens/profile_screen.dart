// ПУТЬ: lib/screens/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants.dart';
import '../widgets/favorite_book_card.dart';
import '../widgets/listened_book_card.dart';
import '../widgets/current_listen_card.dart';
import '../user_notifier.dart';
import 'login_screen.dart'; // Импорт LoginScreen

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> profileFuture;

  @override
  void initState() {
    super.initState();
    // [FIX] Не вызывать в build — иначе будет дергаться при каждом ребилде
    profileFuture = fetchUserProfile();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, dynamic>> fetchUserProfile() async {
    final token = await getToken();
    if (token == null) {
      throw Exception('Токен не найден, пользователь не авторизован');
    }
    final url = Uri.parse('$BASE_URL/profile');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    // Для отладки
    // print('Ответ профиля пользователя: ${response.body}');

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Ошибка: ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  void _continueListening() {
    // Логика перехода к плееру — реализуй по своему проекту
    // Например:
    // Navigator.pushNamed(context, '/player_from_profile');
  }

  /// [ADD] Универсальный резолвер URL с приоритетом на thumb_url.
  /// Поддерживает как относительные пути (через storage/*), так и абсолютные (http/https).
  String? _resolveThumbOrCoverUrl(Map<String, dynamic> book) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // 1) Берём thumb_url, если есть
    String? thumb = pick(book['thumb_url'] ?? book['thumbUrl']);
    if (thumb != null) {
      if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
        return thumb; // уже абсолютный
      }
      // относительный -> собрать абсолютный
      return fullResourceUrl('storage/$thumb');
    }

    // 2) Иначе cover_url
    String? cover = pick(book['cover_url'] ?? book['coverUrl']);
    if (cover != null) {
      if (cover.startsWith('http://') || cover.startsWith('https://')) {
        return cover; // уже абсолютный
      }
      return fullResourceUrl('storage/$cover');
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final userNotifier = Provider.of<UserNotifier>(context);

    // Если не авторизован — сразу LoginScreen
    if (!userNotifier.isAuth) {
      return const LoginScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Личный кабинет')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final favorites = data['favorites'] as List? ?? [];
          final listened = data['listened'] as List? ?? [];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Имя: ${data['name']}', style: const TextStyle(fontSize: 18)),
                Text('Email: ${data['email']}', style: const TextStyle(fontSize: 16)),
                Text(
                  'Статус: ${data['is_paid'] ? 'Платный' : 'Бесплатный'}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),

                // ---- Текущая книга (карточка читает из AudioPlayerProvider) ----
                const Text(
                  'Текущая книга:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                CurrentListenCard(
                  onContinue: _continueListening,
                ),
                const SizedBox(height: 20),

                const Text(
                  'Избранные книги:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                // [MOD] фавориты: теперь используем thumb_url с фолбэком на cover_url
                Expanded(
                  flex: 2,
                  child: favorites.isEmpty
                      ? const Text('Нет избранных книг')
                      : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: favorites.length,
                    itemBuilder: (context, i) {
                      final book = favorites[i] as Map<String, dynamic>;

                      final resolvedUrl = _resolveThumbOrCoverUrl(book);

                      return FavoriteBookCard(
                        book: book,
                        // [MOD] было: fullResourceUrl('storage/$relativeCoverUrl')
                        //      стало: аккуратный резолвер thumb -> cover
                        coverUrl: resolvedUrl,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Прослушанные книги:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                // [MOD] прослушанные: аналогично — thumb_url -> cover_url
                Expanded(
                  flex: 2,
                  child: listened.isEmpty
                      ? const Text('Нет прослушанных книг')
                      : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: listened.length,
                    itemBuilder: (context, i) {
                      final book = listened[i] as Map<String, dynamic>;

                      final resolvedUrl = _resolveThumbOrCoverUrl(book);

                      return ListenedBookCard(
                        book: book,
                        coverUrl: resolvedUrl,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => logout(context),
                      child: const Text('Выйти из аккаунта', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
