// lib/core/ui/app_toast.dart
import 'package:flutter/material.dart';

class AppToast {
  /// Повідомлення про рекламу (Помаранчевий/Жовтий акцент або колір теми)
  static void showAdStarting(BuildContext context) {
    _showStyledToast(
      context,
      text: 'Рекламна пауза... Завантаження',
      icon: Icons.access_time_filled_rounded,
      // Використовуємо вторинний колір для акценту (наприклад, жовтий/помаранчевий в темі)
      // Або просто primary, якщо хочете строгий стиль.
      useWarningColor: false,
    );
  }

  /// Повідомлення "Дякуємо" (Зелений акцент або Primary)
  static void showThankYou(BuildContext context) {
    _showStyledToast(
      context,
      text: 'Дякуємо, що ви з Booka!',
      icon: Icons.favorite_rounded,
      useSuccessColor: true,
    );
  }

  /// Універсальний метод для показу
  static void _showStyledToast(
      BuildContext context, {
        required String text,
        required IconData icon,
        bool useWarningColor = false,
        bool useSuccessColor = false,
      }) {
    // Очищаємо попередні, щоб вони не накопичувались
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Визначаємо колір фону
    Color bgColor = colorScheme.inverseSurface; // Темний сірий (стандарт)
    Color iconColor = colorScheme.onInverseSurface; // Білий (стандарт)
    Color textColor = colorScheme.onInverseSurface;

    if (useSuccessColor) {
      // Для "Дякуємо" можна зробити фіолетовий (брендовий) фон
      bgColor = colorScheme.primary;
      iconColor = colorScheme.onPrimary;
      textColor = colorScheme.onPrimary;
    } else if (useWarningColor) {
      // Для попереджень
      bgColor = colorScheme.tertiary;
      iconColor = colorScheme.onTertiary;
      textColor = colorScheme.onTertiary;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // Гарна іконка у фоні
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            // Текст
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        // 🔥 Стиль плашки
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgColor,
        elevation: 4,
        // Робимо відступи з боків і знизу, щоб вона "парила"
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        // Сильно закруглені кути (капсула)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        // Час показу
        duration: const Duration(seconds: 3),
      ),
    );
  }
}