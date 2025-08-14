// lib/screens/profile_screen.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/constants.dart';
import 'package:booka_app/widgets/favorite_book_card.dart';
import 'package:booka_app/widgets/listened_book_card.dart';
import 'package:booka_app/widgets/current_listen_card.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/screens/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>?> profileFuture;

  @override
  void initState() {
    super.initState();
    profileFuture = fetchUserProfile();
  }

  Future<Map<String, dynamic>?> fetchUserProfile() async {
    try {
      final r = await ApiClient.i().get('/profile');
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(r.data as Map<String, dynamic>);
      }
      // Если 401 или другой код — вернём null (неавторизован / нет данных)
      return null;
    } catch (e) {
      // В debug можно логировать: debugPrint('Profile load error: $e');
      return null;
    }
  }

  Future<void> logout(BuildContext context) async {
    // UserNotifier.logout() очистит токен и обновит состояние
    Provider.of<UserNotifier>(context, listen: false).logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  void _continueListening() {
    // Если у тебя другая логика — можно её вставить сюда.
  }

  /// Универсальный резолвер URL с приоритетом на thumb_url.
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
      body: FutureBuilder<Map<String, dynamic>?>(
        future: profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }

          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('Не удалось загрузить профиль.'));
          }

          final favoritesRaw = data['favorites'];
          final listenedRaw = data['listened'];

          final List<Map<String, dynamic>> favorites = (favoritesRaw is List)
              ? favoritesRaw.cast<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];

          final List<Map<String, dynamic>> listened = (listenedRaw is List)
              ? listenedRaw.cast<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Имя: ${data['name'] ?? '-'}', style: const TextStyle(fontSize: 18)),
                Text('Email: ${data['email'] ?? '-'}', style: const TextStyle(fontSize: 16)),
                Text(
                  'Статус: ${((data['is_paid'] ?? false) as bool) ? 'Платный' : 'Бесплатный'}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),

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

                // Фавориты
                Expanded(
                  flex: 2,
                  child: favorites.isEmpty
                      ? const Text('Нет избранных книг')
                      : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: favorites.length,
                    itemBuilder: (context, i) {
                      final Map<String, dynamic> book = favorites[i];
                      final resolvedUrl = _resolveThumbOrCoverUrl(book);
                      return FavoriteBookCard(book: book, coverUrl: resolvedUrl);
                    },
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Прослушанные книги:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                Expanded(
                  flex: 2,
                  child: listened.isEmpty
                      ? const Text('Нет прослушанных книг')
                      : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: listened.length,
                    itemBuilder: (context, i) {
                      final Map<String, dynamic> book = listened[i];
                      final resolvedUrl = _resolveThumbOrCoverUrl(book);
                      return ListenedBookCard(book: book, coverUrl: resolvedUrl);
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
