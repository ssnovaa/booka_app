import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/user.dart';
import '../user_notifier.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String? error;

  Future<void> login() async {
    setState(() => error = null);
    try {
      final url = Uri.parse('$BASE_URL/login');
      final response = await http.post(url, body: {
        'email': emailController.text.trim(),
        'password': passwordController.text.trim(),
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'];
        final user = User.fromJson(data['user']);
        await Provider.of<UserNotifier>(context, listen: false).login(user, token);

        // Сброс навигационного стека на главный экран с баром!
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
                (route) => false,
          );
        }
      } else {
        setState(() {
          error = 'Неверный логин или пароль';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Ошибка подключения: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
              (route) => false,
        );
        return false; // Не делать стандартный pop!
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Вход')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'E-mail'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Пароль'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: login,
                child: const Text('Войти'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  // Кнопка "Продолжить как гость" — тоже только на MainScreen!
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                        (route) => false,
                  );
                },
                child: const Text('Продолжить как гость'),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
