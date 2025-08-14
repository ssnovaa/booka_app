// lib/screens/entry_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../user_notifier.dart';
import 'main_screen.dart';
import '../core/network/api_client.dart'; // + импорт

class EntryScreen extends StatefulWidget {
  const EntryScreen({Key? key}) : super(key: key);

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    try {
      // Гарантируем, что Dio + кэш хранилище готовы
      await ApiClient.init();

      final userNotifier = Provider.of<UserNotifier>(context, listen: false);
      await userNotifier.checkAuth(); // внутри желательно validateStatus<500 для /profile
    } catch (_) {
      // Тихо игнорим — гость остаётся гостем, логи не засоряем
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Показываем главный экран и для гостя, и для авторизованного
    return const MainScreen();
  }
}
