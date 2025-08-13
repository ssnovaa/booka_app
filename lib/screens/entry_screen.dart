import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../user_notifier.dart';
import 'main_screen.dart';

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
    final userNotifier = Provider.of<UserNotifier>(context, listen: false);
    await userNotifier.checkAuth();
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Показывай MainScreen для всех (и гостя, и авторизованного)
    return const MainScreen();
  }
}
