// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // UserType, getUserType
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';
import 'package:booka_app/core/auth/google_oauth.dart'; // kGoogleWebClientId (Web Client ID из проекта 356…)

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtl = TextEditingController();
  final passCtl = TextEditingController();

  bool _loading = false;
  bool _gLoading = false;
  String? _error;

  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Provider.of<UserNotifier>(context, listen: false)
          .loginWithEmail(emailCtl.text.trim(), passCtl.text.trim());

      final userN = Provider.of<UserNotifier>(context, listen: false);
      final ap = Provider.of<AudioPlayerProvider>(context, listen: false);
      ap.userType = getUserType(userN.user);

      // Запускаем подготовку плеера в фоне
      ap.ensurePrepared();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } on AppNetworkException catch (e) {
      setState(() => _error = e.message ?? 'Помилка входу');
    } catch (e) {
      setState(() => _error = 'Помилка: ${e.toString()}');
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

  /// Вхід через Google → /api/auth/google → збереження токена і профілю
  Future<void> _loginWithGoogle() async {
    if (_gLoading) return;
    setState(() {
      _gLoading = true;
      _error = null;
    });

    try {
      final google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        // Web Client ID з Google Cloud (проект 356…)
        serverClientId: kGoogleWebClientId,
      );

      final acc = await google.signIn();
      if (acc == null) {
        // користувач скасував
        return;
      }
      final auth = await acc.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw 'Не вдалося отримати id_token від Google';
      }

      final r = await ApiClient.i().post(
        '/auth/google',
        data: {'id_token': idToken},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (r.statusCode != 200 || r.data == null) {
        String msg = 'Помилка входу (код ${r.statusCode})';
        try {
          final d = r.data;
          if (d is Map && (d['message'] != null || d['error'] != null)) {
            msg = (d['message'] ?? d['error']).toString();
          } else if (d is String && d.isNotEmpty) {
            msg = d;
          }
        } catch (_) {}
        throw msg;
      }

      final data = r.data as Map;
      final String token =
      (data['token'] ?? data['access_token'] ?? '').toString();
      if (token.isEmpty) throw 'Сервер не повернув токен';

      await AuthStore.I.save(access: token, refresh: null, accessExp: null);

      final userN = Provider.of<UserNotifier>(context, listen: false);
      await userN.fetchCurrentUser();

      final ap = Provider.of<AudioPlayerProvider>(context, listen: false);
      ap.userType = getUserType(userN.user);

      // Запускаем подготовку плеера в фоне
      ap.ensurePrepared();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _gLoading = false);
    }
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
      appBar: bookaAppBar(actions: const []),
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
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                          : const Text('Увійти'),
                    ),
                    const SizedBox(height: 12),

                    // --- Google ---
                    OutlinedButton.icon(
                      onPressed: _gLoading ? null : _loginWithGoogle,
                      icon: _gLoading
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.g_mobiledata, size: 20),
                      label: const Text('Увійти через Google'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Входя, ви приймаєте правила сервісу',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                          theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
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