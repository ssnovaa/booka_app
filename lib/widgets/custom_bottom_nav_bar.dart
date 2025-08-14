// lib/widgets/custom_bottom_nav_bar.dart
import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onPlayerTap;

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    required this.onPlayerTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorSelected = theme.colorScheme.primary;
    final colorUnselected = theme.colorScheme.onSurface.withOpacity(0.6);

    return Material(
      color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Подборки
              IconButton(
                tooltip: 'Подборки',
                icon: Icon(
                  Icons.collections_bookmark,
                  color: currentIndex == 0 ? colorSelected : colorUnselected,
                ),
                onPressed: () => onTap(0),
              ),

              // Каталог
              IconButton(
                tooltip: 'Каталог',
                icon: Icon(
                  Icons.library_books,
                  color: currentIndex == 1 ? colorSelected : colorUnselected,
                ),
                onPressed: () => onTap(1),
              ),

              // Центральная кнопка плеера
              _PlayerFab(
                onTap: onPlayerTap,
                iconColor: theme.colorScheme.onPrimary,
                bgColor: theme.colorScheme.primary,
                ringColor: theme.colorScheme.primary.withOpacity(0.12),
              ),

              // Профиль (кнопка навигации, не вкладка)
              IconButton(
                tooltip: 'Профиль',
                icon: Icon(
                  Icons.account_circle,
                  color: currentIndex == 3 ? colorSelected : colorUnselected,
                ),
                onPressed: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerFab extends StatelessWidget {
  final VoidCallback onTap;
  final Color bgColor;
  final Color ringColor;
  final Color iconColor;

  const _PlayerFab({
    required this.onTap,
    required this.bgColor,
    required this.ringColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Відкрити плеєр',
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Кольцо
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ringColor,
            ),
            // Лого как фоновая картинка
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset('lib/assets/images/logo.png'),
            ),
          ),
          // Кнопка Play с риплом
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                ),
                child: Icon(Icons.play_arrow, color: iconColor, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
