import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'catalog_screen.dart';

class GuestPromptScreen extends StatelessWidget {
  const GuestPromptScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Авторизация'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Вы не вошли в аккаунт',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text('Войти'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const CatalogScreen()),
                      (route) => false,
                );
              },
              child: const Text('Продолжить как гость'),
            ),
          ],
        ),
      ),
    );
  }
}
