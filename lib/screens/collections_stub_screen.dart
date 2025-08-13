import 'package:flutter/material.dart';

class CollectionsStubScreen extends StatelessWidget {
  const CollectionsStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Просто сетка или список "тематических подборок"
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Card(child: ListTile(title: Text('Романтические истории (заглушка)'))),
        Card(child: ListTile(title: Text('Книги для мотивации (заглушка)'))),
        Card(child: ListTile(title: Text('Популярные новинки (заглушка)'))),
        // ...можно сколько угодно
      ],
    );
  }
}
