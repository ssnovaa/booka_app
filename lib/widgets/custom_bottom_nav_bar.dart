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
    final colorSelected = Theme.of(context).colorScheme.primary;
    final colorUnselected = Colors.grey;

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              Icons.collections_bookmark,
              color: currentIndex == 0 ? colorSelected : colorUnselected,
            ),
            onPressed: () => onTap(0),
            tooltip: 'Подборки',
          ),
          IconButton(
            icon: Icon(
              Icons.library_books,
              color: currentIndex == 1 ? colorSelected : colorUnselected,
            ),
            onPressed: () => onTap(1),
            tooltip: 'Каталог',
          ),

          // Кнопка плеера с логотипом и кнопкой play сверху
          GestureDetector(
            onTap: onPlayerTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Image.asset('lib/assets/images/logo.png'),
                  ),
                ),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),

          IconButton(
            icon: Icon(
              Icons.account_circle,
              color: currentIndex == 3 ? colorSelected : colorUnselected,
            ),
            onPressed: () => onTap(3),
            tooltip: 'Профиль',
          ),
        ],
      ),
    );
  }
}
