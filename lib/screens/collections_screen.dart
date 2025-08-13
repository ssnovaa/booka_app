import 'package:flutter/material.dart';

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Тут будут подборки книг',
        style: TextStyle(fontSize: 20),
      ),
    );
  }
}
