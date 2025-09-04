// lib/widgets/google_login_button.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/auth/google_oauth.dart';

typedef OnGoogleSignedIn = Future<void> Function(
    String token,
    Map<String, dynamic> user,
    );

class GoogleLoginButton extends StatefulWidget {
  final OnGoogleSignedIn onSignedIn;
  final String text;

  const GoogleLoginButton({
    Key? key,
    required this.onSignedIn,
    this.text = 'Продовжити через Google',
  }) : super(key: key);

  @override
  State<GoogleLoginButton> createState() => _GoogleLoginButtonState();
}

class _GoogleLoginButtonState extends State<GoogleLoginButton> {
  bool _loading = false;

  /// Обробник натискання на кнопку логіну через Google.
  /// 1. Відкриває діалог вибору акаунту.
  /// 2. Отримує id_token з Google.
  /// 3. Посилає id_token на бекенд (/auth/google).
  /// 4. Викликає onSignedIn(token, user) при успіху.
  Future<void> _handleTap() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      // Використовуємо serverClientId (Web client ID), щоб Google повертав валідний idToken.
      final g = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: kGoogleWebClientId.isNotEmpty ? kGoogleWebClientId : null,
      );

      final acc = await g.signIn();
      if (acc == null) {
        // Користувач відмінив вибір акаунту.
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
        // Показуємо зрозумілу помилку, якщо сервер її повернув.
        String msg = 'Помилка входу (код ${r.statusCode})';
        final d = r.data;
        if (d is Map && (d['message'] != null || d['error'] != null)) {
          msg = (d['message'] ?? d['error']).toString();
        } else if (d is String && d.isNotEmpty) {
          msg = d;
        }
        throw msg;
      }

      final data = (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final token = (data['token'] ?? data['access_token'] ?? '').toString();
      final user = (data['user'] is Map) ? Map<String, dynamic>.from(data['user'] as Map) : <String, dynamic>{};

      if (token.isEmpty) throw 'Сервер не повернув токен';

      await widget.onSignedIn(token, user);
    } catch (e) {
      if (!mounted) return;
      final msg = e?.toString() ?? 'Невідома помилка';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _handleTap,
        icon: _loading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Image.asset(
          'lib/assets/images/google_g.png',
          width: 18,
          height: 18,
          errorBuilder: (_, __, ___) => const Icon(Icons.login, size: 18),
        ),
        label: Text(widget.text),
        style: ElevatedButton.styleFrom(
          backgroundColor: t.colorScheme.surface,
          foregroundColor: t.colorScheme.onSurface,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: t.dividerColor.withOpacity(0.2)),
        ),
      ),
    );
  }
}
