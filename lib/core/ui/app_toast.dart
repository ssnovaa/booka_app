import 'package:flutter/material.dart';

class AppToast {
  AppToast._(); // Приватный конструктор

  /// 🟡 Рекламная пауза
  static void showAdStarting(BuildContext context) {
    _showFancyToast(
      context,
      title: 'Рекламна пауза',
      subtitle: 'Завантаження відео...',
      icon: Icons.access_time_filled_rounded,
      accentColor: Colors.orangeAccent,
    );
  }

  /// 🟢 Благодарность
  static void showThankYou(BuildContext context) {
    _showFancyToast(
      context,
      title: 'Дякуємо!',
      subtitle: 'До скорої зустрічі в Booka',
      icon: Icons.favorite_rounded,
      accentColor: const Color(0xFFE91E63), // Розовый
      isSpecial: true,
    );
  }

  /// 🔴 Ошибка (ДОБАВЛЕНО ДЛЯ ПРОВЕРКИ ИНТЕРНЕТА)
  static void showError(BuildContext context, String message) {
    _showFancyToast(
      context,
      title: 'Увага',
      subtitle: message,
      // Используем rounded, чтобы соответствовать стилю других иконок
      icon: Icons.wifi_off_rounded,
      // Красный цвет ошибки, но не слишком "ядовитый"
      accentColor: const Color(0xFFD32F2F),
    );
  }

  /// 🛠 Основной метод построения
  static void _showFancyToast(
      BuildContext context, {
        required String title,
        String? subtitle,
        required IconData icon,
        required Color accentColor,
        bool isSpecial = false,
      }) {
    // Чистим очередь, чтобы не скапливались старые сообщения
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(bottom: 20),

        content: Stack(
          alignment: Alignment.bottomLeft,
          clipBehavior: Clip.none,
          children: [
            // --- 1. Основная карточка (ФОН) ---
            Padding(
              // Отступ сверху, чтобы иконка физически влезала
              padding: const EdgeInsets.only(top: 30),

              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF252525)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- ВЕРХНИЙ ЭТАЖ: Иконка + Заголовок ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Сдвиг текста вправо под иконку
                        const SizedBox(width: 85),

                        // Заголовок
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.onSurface,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // --- НИЖНИЙ ЭТАЖ: Подпись ---
                    if (subtitle != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // --- 2. Иконка ---
            Positioned(
              top: 0,
              left: 24,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
            ),

            // --- 3. Декор (только если isSpecial) ---
            if (isSpecial)
              Positioned(
                right: 16,
                bottom: 16,
                child: IgnorePointer(
                  child: Icon(
                    Icons.auto_awesome,
                    size: 60,
                    color: accentColor.withOpacity(0.06),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}