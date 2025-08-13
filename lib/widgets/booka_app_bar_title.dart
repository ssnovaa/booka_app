import 'package:flutter/material.dart';

class BookaAppBarTitle extends StatelessWidget {
  const BookaAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          // ИСПРАВЛЕНИЕ: Путь к изображению теперь соответствует вашему pubspec.yaml
          child: Image.asset(
            'lib/assets/images/logo.png',
            width: 40,
            height: 40,
          ),
        ),
        // Оборачиваем Column в Expanded, чтобы он занимал
        // оставшееся доступное пространство и не вызывал переполнения.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'BookaRadio',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Жіночі Аудіокниги українською',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
                // Добавляем overflow, чтобы длинный текст обрезался
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
