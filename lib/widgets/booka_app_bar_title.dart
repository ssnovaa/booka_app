import 'package:flutter/material.dart';

class BookaAppBarTitle extends StatelessWidget {
  const BookaAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Image.asset(
            'lib/assets/images/logo.png',
            width: 48,
            height: 48,
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'BookaRadio',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text(
                  'Жіночі Аудіокниги українською',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
