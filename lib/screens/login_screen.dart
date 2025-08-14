// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // UserType
import 'package:booka_app/widgets/booka_app_bar.dart'; // <-- общий AppBar с глобальной кнопкой темы

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtl = TextEditingController();
  final passCtl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Provider.of<UserNotifier>(context, listen: false)
          .loginWithEmail(emailCtl.text.trim(), passCtl.text.trim());

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } on AppNetworkException catch (e) {
      setState(() => _error = e.message ?? 'Ошибка входа');
    } catch (e) {
      setState(() => _error = 'Ошибка: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    final userNotifier = Provider.of<UserNotifier>(context, listen: false);
    await userNotifier.continueAsGuest();

    final audio = Provider.of<AudioPlayerProvider>(context, listen: false);
    audio.userType = UserType.guest;

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
    );
  }

  @override
  void dispose() {
    emailCtl.dispose();
    passCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // Глобальный AppBar: брендовый заголовок + КНОПКА ТЕМЫ в actions
      appBar: bookaAppBar(
        // свои экшены можно добавить в этот список при необходимости
        actions: const [],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    kToolbarHeight,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Вхід до акаунту',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailCtl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtl,
                      decoration: const InputDecoration(labelText: 'Пароль'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Text('Увійти'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _continueAsGuest,
                      child: const Text('Продовжити як гість'),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
