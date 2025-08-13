import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onPlayerTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context: context,
            index: 0,
            icon: Icons.collections_bookmark_outlined,
            label: 'Подборки',
          ),
          _buildNavItem(
            context: context,
            index: 1,
            icon: Icons.library_books_outlined,
            label: 'Каталог',
          ),
          _buildPlayerButton(context),
          // Пустой элемент-распорка, чтобы центральная кнопка не влияла на позиционирование
          const SizedBox(width: 48),
          _buildNavItem(
            context: context,
            index: 3,
            icon: Icons.account_circle_outlined,
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  // Переиспользуемый виджет для элемента навигации
  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = currentIndex == index;
    final color = isSelected ? theme.colorScheme.primary : Colors.grey[600];

    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: () => onTap(index),
      tooltip: label,
      iconSize: 28,
    );
  }

  // Виджет для центральной кнопки плеера
  Widget _buildPlayerButton(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onPlayerTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
            // Изображение логотипа лучше вынести в assets
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Image.asset('lib/assets/images/logo.png'), // Убедитесь, что путь правильный
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}
