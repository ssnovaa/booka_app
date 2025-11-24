// lib/screens/register_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/widgets/loading_indicator.dart';
import 'package:booka_app/core/security/safe_errors.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // UserType, getUserType
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/screens/notification_permission_screen.dart';

/// Екран реєстрації. Після успішної реєстрації показує екран запиту дозволу на сповіщення.
/// При звичайному вході цей екран не використовується — дозвіл не запитується.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameCtl = TextEditingController();
  final emailCtl = TextEditingController();
  final passCtl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    nameCtl.dispose();
    emailCtl.dispose();
    passCtl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final name = nameCtl.text.trim();
      final email = emailCtl.text.trim();
      final password = passCtl.text.trim();

      if (name.isEmpty || email.isEmpty || password.isEmpty) {
        throw Exception('Будь ласка, заповніть усі поля.');
      }

      // 1) Викликаємо бекенд на реєстрацію
      final r = await ApiClient.i().post(
        '/auth/register',
        data: {'name': name, 'email': email, 'password': password},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (r.statusCode != 200 && r.statusCode != 201) {
        throw Exception('Реєстрація не вдалася (${r.statusCode}).');
      }

      final data = r.data is Map ? r.data as Map : <String, dynamic>{};
      final token = (data['token'] ?? data['access_token'] ?? '').toString();
      if (token.isEmpty) {
        throw Exception('Не отримано токен після реєстрації.');
      }

      // 2) Зберігаємо токен
      await AuthStore.I.save(access: token, refresh: null, accessExp: null);

      // 3) Завантажуємо поточного користувача і накатуємо тип для плеєра
      final userN = Provider.of<UserNotifier>(context, listen: false);
      await userN.fetchCurrentUser();

      final ap = Provider.of<AudioPlayerProvider>(context, listen: false);
      ap.userType = getUserType(userN.user);
      ap.ensurePrepared();

      if (!mounted) return;

      // 4) СРАЗУ після реєстрації питаємо дозвіл на сповіщення
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotificationPermissionScreen(
            onGranted: () {
              // Тут можна підписати користувача на теми або запланувати локальні нотифікації.
            },
            onSkip: () {
              // Користувач відмовився — збережи прапорець, якщо потрібно.
            },
          ),
        ),
      );

      // 5) Після екрана дозволу — на головний
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } on DioException catch (e) {
      setState(() => _error = safeErrorMessage(e));
    } catch (e) {
      setState(() => _error = safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final clamped = media.textScaleFactor.clamp(1.0, 1.35);

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      resizeToAvoidBottomInset: true,
      body: MediaQuery(
        data: media.copyWith(textScaleFactor: clamped),
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + media.viewInsets.bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: media.size.height - media.padding.top - kToolbarHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Створення акаунту',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),

                          TextField(
                            controller: nameCtl,
                            decoration: const InputDecoration(labelText: 'Ім’я'),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: emailCtl,
                            decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: passCtl,
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            obscureText: _obscure,
                            onSubmitted: (_) {
                              if (!_loading) _register();
                            },
                          ),

                          const SizedBox(height: 20),

                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red, fontSize: 14),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                          ElevatedButton(
                            onPressed: _loading ? null : _register,
                            child: _loading
                                ? SizedBox(height: 18, width: 18, child: LoadingIndicator(size: 18))
                                : const Text('Зареєструватися'),
                          ),

                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
