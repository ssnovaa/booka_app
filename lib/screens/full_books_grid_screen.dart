// lib/screens/full_books_grid_screen.dart
import 'dart:async'; // 1️⃣
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/widgets/custom_bottom_nav_bar.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/book_detail_screen.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/widgets/books_grid.dart';
import 'package:booka_app/constants.dart'; // ensureAbsoluteImageUrl

// 2️⃣ Імпорт репозиторію для підписки на зміни
import 'package:booka_app/repositories/profile_repository.dart';

class FullBooksGridScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  /// Поверніть (можливо відносний) URL обкладинки/thumb
  final String? Function(Map<String, dynamic>) resolveUrl;

  /// Зазвичай сюди приходимо з профілю → підсвітимо профіль
  final int currentIndex;

  const FullBooksGridScreen({
    Key? key,
    required this.title,
    required this.items,
    required this.resolveUrl,
    this.currentIndex = 3,
  }) : super(key: key);

  @override
  State<FullBooksGridScreen> createState() => _FullBooksGridScreenState();
}

class _FullBooksGridScreenState extends State<FullBooksGridScreen> {
  // 3️⃣ Локальний стан списку книг
  late List<Map<String, dynamic>> _items;
  StreamSubscription? _updateSub;

  @override
  void initState() {
    super.initState();
    _items = widget.items;

    // 4️⃣ Якщо це екран "Вибране" або "Прослухані", слухаємо зміни в репозиторії
    // (наприклад, коли видалили книгу з вибраного)
    if (widget.title == 'Вибране' || widget.title == 'Прослухані') {
      _updateSub = ProfileRepository.I.onUpdate.listen((_) {
        _refreshListFromCache();
      });
    }
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  /// Оновлюємо список _items з локального кешу ProfileRepository
  void _refreshListFromCache() {
    final map = ProfileRepository.I.getCachedMap();
    if (map == null) return;

    List<dynamic>? rawList;
    if (widget.title == 'Вибране') {
      rawList = map['favorites'];
    } else if (widget.title == 'Прослухані') {
      rawList = map['listened'];
    }

    if (rawList != null) {
      // Конвертуємо raw дані у формат, який очікує Grid
      final List<Map<String, dynamic>> newItems = (rawList is List)
          ? rawList.whereType<Map>().map<Map<String, dynamic>>((m) {
        final out = <String, dynamic>{};
        // ignore: avoid_function_literals_in_foreach_calls
        (m as Map).forEach((k, v) => out['$k'] = v);
        return out;
      }).toList()
          : [];

      if (mounted) {
        setState(() {
          _items = newItems;
        });
      }
    }
  }

  void _goToMain(BuildContext context, int tabIndex) {
    final ms = MainScreen.of(context);
    if (ms != null) {
      ms.setTab(tabIndex);     // 0 — жанри, 1 — каталог
      // Закриваємо поточний екран і профіль під ним (якщо є),
      // щоб повернутися на MainScreen.
      Navigator.of(context).pop();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } else {
      // Фолбек, якщо раптово поза MainScreen
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

  /// Нормалізуємо карту книги: примусово робимо абсолютні URL для мініатюри/обкладинки
  Map<String, dynamic> _normalizedMap(
      Map<String, dynamic> m,
      String? Function(Map<String, dynamic>) parentResolveUrl,
      ) {
    final map = Map<String, dynamic>.from(m);

    // 1) Найкращий URL через resolveUrl батька
    String? best = parentResolveUrl.call(map);

    // 2) Якщо батько не дав — пробуємо стандартні поля
    best ??= map['thumb_url']?.toString();
    best ??= map['thumbUrl']?.toString();
    best ??= map['cover_url']?.toString();
    best ??= map['coverUrl']?.toString();

    // 3) Робимо абсолютним
    final abs = ensureAbsoluteImageUrl(best);

    // 4) Зберігаємо
    if (abs != null) {
      map['thumb_url'] = abs;
      map['thumbUrl'] = abs;
      map['cover_url'] = abs;
      map['coverUrl'] = abs;
    }

    return map;
  }

  /// Обгортка над resolveUrl: завжди віддає абсолютний URL.
  String? _resolvedAbsolute(
      Map<String, dynamic> m,
      String? Function(Map<String, dynamic>) parentResolveUrl,
      ) {
    return ensureAbsoluteImageUrl(parentResolveUrl(m));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 5️⃣ Використовуємо _items (який може оновлюватися), а не widget.items
    final normalizedItems = _items
        .map((m) => _normalizedMap(m, widget.resolveUrl))
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
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              // Використовуємо готовий віджет з клікабельними картками
              child: BooksGrid(
                items: normalizedItems,
                resolveUrl: (m) => _resolvedAbsolute(m, widget.resolveUrl),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: widget.currentIndex, // зазвичай 3 (профіль)
        onTap: (i) {
          if (i == 0 || i == 1) _goToMain(context, i);
          if (i == 2) _openPlayer(context);
          if (i == 3) {
            // Ми вже над профілем → просто повернемося
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
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