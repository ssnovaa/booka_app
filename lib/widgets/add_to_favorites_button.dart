
// ШЛЯХ: lib/widgets/add_to_favorites_button.dart
//
// Просте «серце» для додавання книги у вибране (мінімальна логіка):
// - Натискання → POST /favorites/{id}
// - Показує невеликий лоадер під час запиту
// - Після успіху блокується і показує заповнене серце
// - Якщо користувач не авторизований — показує підказку (SnackBar)
//
// Коментарі — українською.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/favorites_api.dart';
import 'package:booka_app/user_notifier.dart';

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
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final isAuth = context.watch<UserNotifier>().isAuth;
    final iconSize = widget.size ?? (widget.style == AddFavStyle.overlay ? 20.0 : 24.0);
    final ColorScheme cs = Theme.of(context).colorScheme;

    final icon = _done ? Icons.favorite : Icons.favorite_border;
    Color? color;
    if (widget.style == AddFavStyle.overlay) {
      color = Colors.white;
    } else {
      color = cs.primary;
    }

    Widget btn = IconButton(
      icon: _busy
          ? SizedBox(width: iconSize, height: iconSize, child: const CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: iconSize),
      color: _done ? Colors.redAccent : color,
      onPressed: _busy
          ? null
          : () async {
        if (!isAuth) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Увійдіть, щоб додавати у вибране')),
          );
          return;
        }
        try {
          setState(() => _busy = true);
          await FavoritesApi.add(widget.bookId);
          if (!mounted) return;
          setState(() => _done = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Додано у «Вибране»')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не вдалося додати у «Вибране»: $e')),
          );
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
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
