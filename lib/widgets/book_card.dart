// ШЛЯХ: lib/widgets/book_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../screens/book_detail_screen.dart';
import 'package:booka_app/screens/series_books_list_screen.dart';
import 'package:booka_app/widgets/loading_indicator.dart';
import 'package:booka_app/core/utils/duration_format.dart'; // ← форматер тривалості
import 'package:booka_app/core/network/api_client.dart'; // ← мережевий клієнт
import 'package:booka_app/core/security/safe_errors.dart'; // ← санітизація повідомлень про помилки
import 'package:booka_app/user_notifier.dart'; // ← перевірка авторизації
import 'package:booka_app/screens/login_screen.dart'; // ← перехід на логін для гостей

class BookCardWidget extends StatelessWidget {
  final Book book;

  const BookCardWidget({Key? key, required this.book}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageUrl = (book.displayCoverUrl).trim();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    const double cardRadius = 14;
    const double imageWidth = 96;
    const double vPad = 12;
    const double hPad = 12;

    final String? seriesTitle = (() {
      final s = book.series;
      return (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    })();

    void openSeries() {
      if (book.seriesId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesBooksListScreen(
              title: seriesTitle ?? 'Серія',
              seriesId: book.seriesId!.toString(),
            ),
          ),
        );
        return;
      }
      if (seriesTitle != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesBooksListScreen(
              title: seriesTitle,
              seriesId: seriesTitle,
            ),
          ),
        );
      }
    }

    // ✅ Форматуємо тривалість у години та хвилини (українські позначення)
    final prettyDuration = formatBookDuration(book.duration, locale: 'uk');

    // Спробуємо визначити початковий стан «вибране» з моделі (якщо бекенд віддає прапор)
    bool initialFav = false;
    try {
      final dyn = book as dynamic;
      final v = dyn.isFavorite ?? dyn.is_favorite ?? dyn.favorite ?? dyn.inFavorites ?? dyn.in_favorites;
      if (v is bool) initialFav = v;
      if (v is num) initialFav = v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == '1' || s == 'true' || s == 'yes') initialFav = true;
      }
    } catch (_) {}

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
        );
      },
      borderRadius: BorderRadius.circular(cardRadius),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withOpacity(0.25) : Colors.black12,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: theme.dividerColor.withOpacity(isDark ? 0.15 : 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Обкладинка (без оверлея серця)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: imageWidth,
                  height: imageWidth * 1.5,
                  color: isDark ? Colors.white10 : Colors.black12,
                  alignment: Alignment.center,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: imageWidth,
                    height: imageWidth * 1.5,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      width: 22,
                      height: 22,
                      child: LoadingIndicator(size: 22),
                    ),
                    errorWidget: (context, url, error) => Icon(
                      Icons.broken_image,
                      size: 36,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  )
                      : Icon(
                    Icons.book,
                    size: 40,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Текстова частина
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: imageWidth * 1.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (book.title).trim().isNotEmpty ? book.title.trim() : 'Без назви',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if ((book.author).trim().isNotEmpty)
                        Text(
                          book.author.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (seriesTitle != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: openSeries,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Серія: ', style: theme.textTheme.bodySmall),
                                TextSpan(
                                  text: seriesTitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.primary,
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      if (book.genres.isNotEmpty)
                        Text(
                          'Жанри: ${book.genres.take(3).join(", ")}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),

                      // 🔻 Рядок метаданих: [тривалість] [❤️] (серія тут не дублюється, вона вище)
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (prettyDuration.isNotEmpty)
                            _MetaChip(icon: Icons.schedule, text: prettyDuration),
                          _FavoriteInlineButton(
                            bookId: book.id,
                            initialIsFav: initialFav,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка «сердечко» прямо в ряду метаданих — відразу після тривалості.
/// onPressed завжди встановлений; під час запиту просто рано виходимо, щоб подія не пішла в батьківський InkWell.
class _FavoriteInlineButton extends StatefulWidget {
  final int bookId;
  final bool initialIsFav;

  const _FavoriteInlineButton({
    required this.bookId,
    required this.initialIsFav,
  });

  @override
  State<_FavoriteInlineButton> createState() => _FavoriteInlineButtonState();
}

class _FavoriteInlineButtonState extends State<_FavoriteInlineButton> {
  bool _busy = false;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _isFav = widget.initialIsFav;
  }

  Future<void> _toggle() async {
    if (_busy) return;

    final userN = context.read<UserNotifier>();
    if (!userN.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Увійдіть, щоб керувати «Вибраним»'),
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

    final wantFav = !_isFav;
    setState(() => _busy = true);
    try {
      if (wantFav) {
        await ApiClient.i().post('/favorites/${widget.bookId}');
      } else {
        await ApiClient.i().delete('/favorites/${widget.bookId}');
      }
      if (!mounted) return;
      setState(() => _isFav = wantFav);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wantFav ? 'Додано у «Вибране»' : 'Прибрано з «Вибраного»')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = safeErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      height: 24,
      child: IconButton(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
        iconSize: 18,
        tooltip: _isFav ? 'Прибрати з «Вибраного»' : 'Додати у «Вибране»',
        onPressed: () {
          if (_busy) return;
          _toggle();
        },
        icon: _busy
            ? const SizedBox(
          width: 16,
          height: 16,
          child: LoadingIndicator(size: 16),
        )
            : Icon(
          _isFav ? Icons.favorite : Icons.favorite_border,
          color: _isFav ? Colors.redAccent : t.colorScheme.primary,
          size: 18,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withOpacity(isDark ? 0.18 : 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.iconTheme.color?.withOpacity(0.75)),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
