import 'package:flutter/material.dart';

class CollectionsStubScreen extends StatelessWidget {
  const CollectionsStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Просто сітка чи список "тематичних добірок"
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Card(child: ListTile(title: Text('Романтичні історії (заглушка)'))),
        Card(child: ListTile(title: Text('Книги для мотивації (заглушка)'))),
        Card(child: ListTile(title: Text('Популярні новинки (заглушка)'))),
        // ...можна скільки завгодно
      ],
    );
  }
}
