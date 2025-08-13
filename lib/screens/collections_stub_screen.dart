import 'package:flutter/material.dart';

class CollectionsStubScreen extends StatelessWidget {
  const CollectionsStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Используем ListView.separated для автоматического добавления отступов
    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: 3, // Количество подборок
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        // Здесь можно будет загружать данные о подборках из сети
        const collections = [
          _CollectionCard(
            title: 'Романтические истории',
            icon: Icons.favorite_border_rounded,
            color: Colors.pink,
          ),
          _CollectionCard(
            title: 'Книги для мотивации',
            icon: Icons.lightbulb_outline_rounded,
            color: Colors.orange,
          ),
          _CollectionCard(
            title: 'Популярные новинки',
            icon: Icons.star_border_rounded,
            color: Colors.blue,
          ),
        ];
        return collections[index];
      },
    );
  }
}

// Отдельный виджет для карточки подборки
class _CollectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _CollectionCard({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: Реализовать переход к экрану деталей подборки
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Переход к подборке "$title"')),
          );
        },
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.7), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
