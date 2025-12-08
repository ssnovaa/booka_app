// ШЛЯХ: lib/widgets/add_to_favorites_button.dart
//
// Розумне «серце» для вибраного з підтримкою реактивності:
// - Автоматично визначає початковий стан (чи є книга у профілі)
// - Слухає зміни через ProfileRepository (якщо змінили в іншому місці — тут оновиться)
// - Працює як Toggle (Додати / Видалити)
// - Використовує FavoritesApi для запитів

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/favorites_api.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/repositories/profile_repository.dart';
import 'package:booka_app/core/security/safe_errors.dart';
import 'package:booka_app/screens/login_screen.dart';

enum AddFavStyle { overlay, bar }

class AddToFavoritesButton extends StatefulWidget {
  final int bookId;
  final AddFavStyle style;
  final double? size;

  const AddToFavoritesButton({
    super.key,
    required this.bookId,
    this.style = AddFavStyle.overlay,
    this.size,
  });

  @override
  State<AddToFavoritesButton> createState() => _AddToFavoritesButtonState();
}

class _AddToFavoritesButtonState extends State<AddToFavoritesButton> {
  bool _busy = false;
  bool _isFav = false;
  StreamSubscription? _updateSub;

  @override
  void initState() {
    super.initState();
    _checkStatusFromCache();

    // Підписуємося на глобальні оновлення профілю
    _updateSub = ProfileRepository.I.onUpdate.listen((_) {
      if (mounted) {
        _checkStatusFromCache();
      }
    });
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  /// Перевіряє, чи є ця книга у списку вибраного в кеші профілю
  void _checkStatusFromCache() {
    final map = ProfileRepository.I.getCachedMap();
    if (map == null) return;

    final rawFavs = map['favorites'];
    bool found = false;

    if (rawFavs is List) {
      for (final item in rawFavs) {
        // Парсимо ID книги з різних можливих структур
        int? id;
        if (item is int) {
          id = item;
        } else if (item is Map) {
          // Зазвичай ID книги це 'id', але може бути 'book_id'
          final rawId = item['id'] ?? item['book_id'] ?? item['bookId'];
          if (rawId != null) {
            id = int.tryParse(rawId.toString());
          }
        }

        if (id == widget.bookId) {
          found = true;
          break;
        }
      }
    }

    if (found != _isFav) {
      setState(() => _isFav = found);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;

    final userNotifier = context.read<UserNotifier>();
    if (!userNotifier.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Увійдіть, щоб додавати у вибране'),
          action: SnackBarAction(
            label: 'Увійти',
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ),
      );
      return;
    }

    final wasFav = _isFav;
    // Оптимістичне оновлення інтерфейсу
    setState(() {
      _busy = true;
      _isFav = !wasFav;
    });

    try {
      if (!wasFav) {
        // Було false -> додаємо
        await FavoritesApi.add(widget.bookId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Додано у «Вибране»'), duration: Duration(seconds: 1)),
          );
        }
      } else {
        // Було true -> видаляємо
        await FavoritesApi.remove(widget.bookId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Прибрано з «Вибраного»'), duration: Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      // Відкат при помилці
      if (mounted) {
        setState(() => _isFav = wasFav);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(safeErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = widget.size ?? (widget.style == AddFavStyle.overlay ? 20.0 : 24.0);

    final iconData = _isFav ? Icons.favorite : Icons.favorite_border;

    Color iconColor;
    if (_isFav) {
      iconColor = Colors.redAccent;
    } else {
      iconColor = (widget.style == AddFavStyle.overlay) ? Colors.white : cs.primary;
    }

    Widget btn = IconButton(
      icon: _busy
          ? SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(strokeWidth: 2)
      )
          : Icon(iconData, size: iconSize),
      color: iconColor,
      tooltip: _isFav ? 'Прибрати з вибраного' : 'Додати у вибране',
      onPressed: _toggle,
    );

    if (widget.style == AddFavStyle.overlay) {
      // Невелика напівпрозора підкладка для кращої видимості на обкладинці
      btn = Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: btn,
      );
    }

    return btn;
  }
}