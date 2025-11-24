import 'package:flutter/material.dart';

/// ⛔️ Універсальний аркуш із попередженням про обмежений доступ.
/// Викликається з будь-якого місця: AccessLimitSheet.show(context, ...);
class AccessLimitSheet {
  /// Показати модальний аркуш.
  /// [onLogin] — дія переходу на екран логіну.
  /// [onTryFirstChapter] — дія для «Спробувати 1-шу главу» (опційно).
  static Future<void> show(
      BuildContext context, {
        VoidCallback? onLogin,
        VoidCallback? onTryFirstChapter,
        String? title,
        String? message,
      }) async {
    // ⚙️ Адаптивність: звужуємо на планшетах/широких екранах
    final Widget sheet = _SheetContent(
      title: title ?? 'Доступ обмежено',
      message: message ??
          'У гостьовому режимі доступна лише перша глава. '
              'Увійдіть, щоб отримати повний доступ до всіх розділів і керування прогресом.',
      onLogin: onLogin,
      onTryFirstChapter: onTryFirstChapter,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // краще поводиться на малих екранах та з клавіатурою
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return LayoutBuilder(
          builder: (ctx, c) {
            // Обмеження ширини для планшетів/desktop
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: sheet,
              ),
            );
          },
        );
      },
    );
  }
}

class _SheetContent extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onLogin;
  final VoidCallback? onTryFirstChapter;

  const _SheetContent({
    super.key,
    required this.title,
    required this.message,
    this.onLogin,
    this.onTryFirstChapter,
  });

  @override
  Widget build(BuildContext context) {
    // 📱 Дбайлива робота з масштабом шрифтів, щоб текст завжди поміщався
    final media = MediaQuery.of(context);
    final clampedScale =
    media.textScaleFactor.clamp(1.0, 1.3); // не даємо тексту «зламати» верстку

    return MediaQuery(
      data: media.copyWith(textScaleFactor: clampedScale),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          // додаємо відступ знизу під жест навігації/кнопки
          bottom: 20 + media.padding.bottom,
          top: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            // 🟣 Основна дія — Увійти/Зареєструватися
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).maybePop();
                  onLogin?.call();
                },
                child: const Text('Увійти / Зареєструватися'),
              ),
            ),
            const SizedBox(height: 8),
            // ⚪️ Додаткова дія — Спробувати 1-шу главу (опційно)
            if (onTryFirstChapter != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).maybePop();
                    onTryFirstChapter?.call();
                  },
                  child: const Text('Спробувати 1-шу главу'),
                ),
              ),
            const SizedBox(height: 4),
            // Третя дія — Закрити
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Закрити'),
            ),
          ],
        ),
      ),
    );
  }
}
