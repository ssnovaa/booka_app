// lib/core/ui/reward_confirm_dialog.dart
// Комментарии — русские; тексты — украинские.
// Полноэкранное подтверждение награды с автозакрытием и одной большой кнопкой.

import 'package:flutter/material.dart';

Future<void> showRewardConfirmDialog(
    BuildContext context, {
      required String title,              // напр.: '+15 хв нараховано'
      String? subtitle,                   // напр.: 'Дякуємо за перегляд реклами'
      Duration autoClose = const Duration(seconds: 7),
      VoidCallback? onClosed,
    }) async {
  bool closed = false;

  Future.delayed(autoClose, () {
    if (!closed && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  });

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    closed = true;
                    Navigator.of(ctx).pop();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Продовжити',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Вікно закриється автоматично за кілька секунд',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    },
  );

  onClosed?.call();
}
