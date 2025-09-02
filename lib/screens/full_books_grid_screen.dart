// lib/screens/full_books_grid_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/widgets/custom_bottom_nav_bar.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/book_detail_screen.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/widgets/books_grid.dart';
import 'package:booka_app/constants.dart'; // ensureAbsoluteImageUrl

class FullBooksGridScreen extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  /// Верните (возможно относительный) URL обложки/thumb
  final String? Function(Map<String, dynamic>) resolveUrl;

  /// Обычно сюда приходим из профиля → подсветим профиль
  final int currentIndex;

  const FullBooksGridScreen({
    Key? key,
    required this.title,
    required this.items,
    required this.resolveUrl,
    this.currentIndex = 3,
  }) : super(key: key);

  void _goToMain(BuildContext context, int tabIndex) {
    final ms = MainScreen.of(context);
    if (ms != null) {
      ms.setTab(tabIndex);     // 0 — жанры, 1 — каталог
      // Закрываем текущий экран и профиль под ним (если есть),
      // чтобы вернуться на MainScreen.
      Navigator.of(context).pop();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } else {
      // Фолбэк, если внезапно вне MainScreen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainScreen(initialIndex: tabIndex)),
            (route) => false,
      );
    }
  }

  Future<void> _openPlayer(BuildContext context) async {
    final ap = context.read<AudioPlayerProvider>();
    final book = ap.currentBook;
    if (book != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Немає поточного прослуховування')),
      );
    }
  }

  /// Нормализуем карту книги: принудительно делаем абсолютные URL для миниатюры/обложки,
  /// чтобы не ловить «No host specified» на старых данных.
  Map<String, dynamic> _normalizedMap(
      Map<String, dynamic> m,
      String? Function(Map<String, dynamic>) parentResolveUrl,
      ) {
    final map = Map<String, dynamic>.from(m);

    // 1) Лучший URL через resolveUrl родителя (как в превью профиля)
    String? best = parentResolveUrl.call(map);

    // 2) Если родитель не дал — пробуем стандартные поля
    best ??= map['thumb_url']?.toString();
    best ??= map['thumbUrl']?.toString();
    best ??= map['cover_url']?.toString();
    best ??= map['coverUrl']?.toString();

    // 3) Делаем абсолютным (covers/... → https://.../storage/covers/...)
    final abs = ensureAbsoluteImageUrl(best);

    // 4) Сохраняем во все известные поля (на всякий)
    if (abs != null) {
      map['thumb_url'] = abs;
      map['thumbUrl'] = abs;
      map['cover_url'] = abs;
      map['coverUrl'] = abs;
    }

    return map;
  }

  /// Обёртка над resolveUrl: всегда отдаёт абсолютный URL.
  String? _resolvedAbsolute(
      Map<String, dynamic> m,
      String? Function(Map<String, dynamic>) parentResolveUrl,
      ) {
    return ensureAbsoluteImageUrl(parentResolveUrl(m));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Нормализуем список заранее (lazy недорого)
    final normalizedItems = items
        .map((m) => _normalizedMap(m, resolveUrl))
        .toList(growable: false);

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              // Используем готовый виджет с кликабельными карточками:
              // он сам делает Book.fromJson(...) и открывает BookDetailScreen.
              child: BooksGrid(
                items: normalizedItems,
                resolveUrl: (m) => _resolvedAbsolute(m, resolveUrl),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: currentIndex, // обычно 3 (профиль)
        onTap: (i) {
          if (i == 0 || i == 1) _goToMain(context, i);
          if (i == 2) _openPlayer(context);
          if (i == 3) {
            // Мы уже над профилем → просто вернёмся
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              // редкий случай: попросим MainScreen открыть профиль
              final ms = MainScreen.of(context);
              if (ms != null) ms.setTab(3);
            }
          }
        },
        onOpenPlayer: () => _openPlayer(context),
        onPlayerTap: () => _openPlayer(context),
      ),
    );
  }
}
