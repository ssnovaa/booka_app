// lib/widgets/booka_app_bar_title.dart
import 'package:flutter/material.dart';

class BookaAppBarTitle extends StatelessWidget {
  const BookaAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(
            label: 'Логотип BookaRadio',
            child: Image.asset(
              'lib/assets/images/logo.png',
              width: 40,
              height: 40,
            ),
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'BookaRadio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              Text(
                'Жіночі аудіокниги українською',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurfaceVariant,
                  fontSize: 13,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
