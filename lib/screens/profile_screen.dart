// ПУТЬ: lib/screens/profile_screen.dart

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
import 'package:booka_app/widgets/booka_app_bar.dart'; // <-- глобальный AppBar с переключателем темы
import 'package:dio/dio.dart';

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
      final r = await ApiClient.i().get(
        '/profile',
        options: Options(
          // 401/404 не считаем ошибкой — гость. Кэш для профиля не используем.
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(r.data as Map<String, dynamic>);
      }
      // 401/404 → null (неавторизован / нет данных)
      return null;
    } catch (_) {
      // Можно залогировать в debug при необходимости
      return null;
    }
  }

  Future<void> logout(BuildContext context) async {
    Provider.of<UserNotifier>(context, listen: false).logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  void _continueListening() {
    // Твоя логика "продолжить прослушивание", если нужна
  }

  /// thumb_url > cover_url; относительные пути → абсолютные через fullResourceUrl('storage/...').
  String? _resolveThumbOrCoverUrl(Map<String, dynamic> book) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? thumb = pick(book['thumb_url'] ?? book['thumbUrl']);
    if (thumb != null) {
      if (thumb.startsWith('http://') || thumb.startsWith('https://')) return thumb;
      return fullResourceUrl('storage/$thumb');
    }

    String? cover = pick(book['cover_url'] ?? book['coverUrl']);
    if (cover != null) {
      if (cover.startsWith('http://') || cover.startsWith('https://')) return cover;
      return fullResourceUrl('storage/$cover');
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final userNotifier = Provider.of<UserNotifier>(context);

    // Если не авторизован — сразу показываем LoginScreen (в нём уже есть глобальный переключатель темы)
    if (!userNotifier.isAuth) {
      return const LoginScreen();
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: bookaAppBar(
        actions: const [], // глобальная кнопка темы уже встроена
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Помилка: ${snapshot.error}'));
          }

          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('Не вдалося завантажити профіль.'));
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
                Text('Імʼя: ${data['name'] ?? '-'}', style: theme.textTheme.titleMedium),
                Text('Email: ${data['email'] ?? '-'}', style: theme.textTheme.bodyMedium),
                Text(
                  'Статус: ${((data['is_paid'] ?? false) as bool) ? 'Платний' : 'Безкоштовний'}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),

                Text('Поточна книга:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                CurrentListenCard(onContinue: _continueListening),
                const SizedBox(height: 20),

                Text('Вибране:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                // Избранные
                Expanded(
                  flex: 2,
                  child: favorites.isEmpty
                      ? const Text('Немає обраних книг')
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

                Text('Прослухані:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                Expanded(
                  flex: 2,
                  child: listened.isEmpty
                      ? const Text('Немає прослуханих книг')
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
                      child: const Text('Вийти з акаунту', style: TextStyle(fontSize: 18)),
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
