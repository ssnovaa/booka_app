import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../user_notifier.dart';
import 'main_screen.dart';

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Используем Consumer, чтобы реагировать на изменение статуса аутентификации
    return Consumer<UserNotifier>(
      builder: (context, userNotifier, child) {
        // Пока UserNotifier проверяет токен, показываем экран загрузки
        if (userNotifier.status == AuthStatus.authenticating ||
            userNotifier.status == AuthStatus.uninitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Когда проверка завершена (успешно или нет), показываем главный экран.
        // MainScreen сам решит, что показать гостю или авторизованному пользователю.
        return const MainScreen();
      },
    );
  }
}
