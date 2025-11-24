// lib/screens/login_screen.dart
import 'dart:ui'; // для BackdropFilter (легкий блюр на оверлеї)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart'; // UserType, getUserType
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';
import 'package:booka_app/core/auth/google_oauth.dart'; // kGoogleWebClientId (Web Client ID)
import 'package:booka_app/widgets/loading_indicator.dart'; // Lottie-лоадер
import 'package:booka_app/core/security/safe_errors.dart'; // санітизатор повідомлень

// ⬇️ Запит дозволу лише після РЕЄСТРАЦІЇ
import 'package:booka_app/screens/notification_permission_screen.dart';

/// Екран входу і реєстрації — увесь текст інтерфейсу українською, коментарі українською.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtl = TextEditingController();
  final passCtl = TextEditingController();

  bool _loading = false;   // стан запиту для email/пароль
  bool _gLoading = false;  // стан запиту для Google
  String? _error;

  // 🔖 Текст підказки для глобального індикатора (щоб було зрозуміло, на якому кроці ми чекаємо)
  String? _progressText;

  bool _isRegisterMode = false; // false — вхід, true — реєстрація
  bool _obscure = true;         // показ/приховати пароль

  // 🔐 Вхід по email/пароль
  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _progressText = 'Виконуємо вхід…';
      _error = null;
    });

    try {
      await Provider.of<UserNotifier>(context, listen: false)
          .loginWithEmail(emailCtl.text.trim(), passCtl.text.trim());

      final userN = Provider.of<UserNotifier>(context, listen: false);
      final ap = Provider.of<AudioPlayerProvider>(context, listen: false);
      ap.userType = getUserType(userN.user);

      // 🎧 Підготуємо плеєр у фоновому режимі
      ap.ensurePrepared();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } on AppNetworkException catch (e) {
      setState(() => _error = safeErrorMessage(e));
    } catch (e) {
      setState(() => _error = safeErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progressText = null;
        });
      }
    }
  }

  // 🆕 Реєстрація по email/пароль — ПИТАЄМО ДОЗВІЛ лише після успішної реєстрації
  Future<void> _doRegister() async {
    setState(() {
      _loading = true;
      _progressText = 'Створюємо акаунт…';
      _error = null;
    });

    try {
      final email = emailCtl.text.trim();
      final password = passCtl.text.trim();

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Будь ласка, заповніть email та пароль.');
      }

      // 1) Виклик бекенду на реєстрацію
      final r = await ApiClient.i().post(
        '/auth/register',
        data: {'email': email, 'password': password},
      );

      if (r.statusCode != 200 && r.statusCode != 201) {
        throw Exception('Реєстрація не вдалася (${r.statusCode}). Спробуйте ще раз.');
      }

      // 2) Отримання токена
      final data = r.data is Map ? r.data as Map : <String, dynamic>{};
      final token = (data['token'] ?? data['access_token'] ?? '').toString();
      if (token.isEmpty) {
        throw Exception('Не отримано токен після реєстрації.');
      }

      // 3) Зберегти токен
      await AuthStore.I.save(access: token, refresh: null, accessExp: null);

      // 4) Оновити користувача та підготувати плеєр
      setState(() => _progressText = 'Оновлюємо дані акаунту…');
      final userN = Provider.of<UserNotifier>(context, listen: false);
      await userN.fetchCurrentUser();

      final ap = Provider.of<AudioPlayerProvider>(context, listen: false);
      ap.userType = getUserType(userN.user);
      ap.ensurePrepared();

      if (!mounted) return;

      // 5) ЛИШЕ ПІСЛЯ РЕЄСТРАЦІЇ — екран запиту дозволу
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotificationPermissionScreen(
            onGranted: () {},
            onSkip: () {},
          ),
        ),
      );

      // 6) На головний екран
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } catch (e) {
      setState(() => _error = safeErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progressText = null;
        });
      }
    }
  }

  // 🚪 Продовжити як гість
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

  // 🟦 Вхід через Google: показуємо чітку індикацію на КОЖНОМУ кроці (вікно Google → отримання токена → бекенд)
  Future<void> _loginWithGoogle() async {
    if (_gLoading) return;
    setState(() {
      _gLoading = true;
      _progressText = 'Відкриваємо Google…';
      _error = null;
    });

    try {
      final google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: kGoogleWebClientId,
      );

      // Крок 1: відкриття вікна Google та вибір акаунту
      final acc = await google.signIn();
      if (acc == null) {
        // Користувач скасував авторизацію — просто вийдемо без помилки
        return;
      }

      setState(() => _progressText = 'Отримуємо підтвердження від Google…');

      // Крок 2: отримання токена від Google
      final auth = await acc.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('GOOGLE_ID_TOKEN_MISSING');
      }

      setState(() => _progressText = 'Підтверджуємо вхід на сервері Booka…');

      // Крок 3: бекенд-верифікація
      final r = await ApiClient.i().post(
        '/auth/google',
        data: {'id_token': idToken},
      );

      // Дозволимо 200 (вхід) і 201 (новий користувач)
      if ((r.statusCode != 200 && r.statusCode != 201) || r.data == null) {
        throw Exception('GOOGLE_LOGIN_FAILED_${r.statusCode ?? ''}');
      }

      final data = r.data as Map;
      final String token = (data['token'] ?? data['access_token'] ?? '').toString();
      if (token.isEmpty) {
        throw Exception('GOOGLE_TOKEN_MISSING');
      }

      // Зберігаємо токен у AuthStore
      await AuthStore.I.save(access: token, refresh: null, accessExp: null);

      // Оновити користувача та плеєр
      setState(() => _progressText = 'Оновлюємо дані акаунту…');
      final userN = Provider.of<UserNotifier>(context, listen: false);
      await userN.fetchCurrentUser();

      final ap = Provider.of<AudioPlayerProvider>(context, listen: false);
      ap.userType = getUserType(userN.user);
      ap.ensurePrepared();

      if (!mounted) return;

      // Визначаємо, чи це реєстрація через Google
      final bool isNewUser =
          r.statusCode == 201 ||
              data['is_new_user'] == true ||
              data['is_new'] == true ||
              data['new_user'] == true ||
              data['first_login'] == true;

      if (isNewUser) {
        // Питаємо дозвіл на сповіщення лише для нових користувачів
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NotificationPermissionScreen(
              onGranted: () {},
              onSkip: () {},
            ),
          ),
        );
      }

      // На головний екран
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeErrorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _gLoading = false;
          _progressText = null;
        });
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_isRegisterMode) {
      await _doRegister();
    } else {
      await _doLogin();
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
    final media = MediaQuery.of(context);

    // 🔤 Обмеження системного масштабу шрифту, щоб верстка не «стрибала»
    final clampedScale = media.textScaleFactor.clamp(1.0, 1.3);

    // ✅ Прапорець глобального оверлея (показуємо поверх усього контенту, коли триває будь-який запит)
    final bool isBlocking = _loading || _gLoading;

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      resizeToAvoidBottomInset: true, // ⌨️ вміст підтискається клавіатурою
      body: MediaQuery(
        data: media.copyWith(textScaleFactor: clampedScale),
        child: SafeArea(
          child: Stack(
            children: [
              // Основний контент
              GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(), // тап поза полями ховає клавіатуру
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  // ⌨️ додаємо відступ знизу під клавіатуру
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + media.viewInsets.bottom),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520), // 📱 обмежуємо ширину форми на планшетах/ландшафті
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          // Робимо мінімальну висоту ~екрана, щоб Spacer працював коректно
                          minHeight: media.size.height - media.padding.top - kToolbarHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                _isRegisterMode ? 'Створення акаунту' : 'Вхід до акаунту',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),

                              // 📧 Email
                              TextField(
                                controller: emailCtl,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  hintText: 'you@example.com',
                                ),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),

                              // 🔑 Пароль
                              TextField(
                                controller: passCtl,
                                decoration: InputDecoration(
                                  labelText: 'Пароль',
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'Показати пароль' : 'Приховати пароль',
                                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_loading) _submit();
                                },
                              ),
                              const SizedBox(height: 20),

                              // Повідомлення про помилку (санітизоване)
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

                              // Основна кнопка: Увійти або Зареєструватися
                              ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: LoadingIndicator(size: 18),
                                )
                                    : Text(_isRegisterMode ? 'Зареєструватися' : 'Увійти'),
                              ),
                              const SizedBox(height: 12),

                              // 🟦 Кнопка входу через Google (використовується і як реєстрація через Google)
                              OutlinedButton.icon(
                                onPressed: _gLoading ? null : _loginWithGoogle,
                                icon: _gLoading
                                    ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: LoadingIndicator(size: 18),
                                )
                                    : const Icon(Icons.g_mobiledata, size: 20), // можна замінити на власну іконку Google
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
                                  _isRegisterMode
                                      ? 'Зареєструвавшись, ви погоджуєтесь з правилами сервісу'
                                      : 'Увійшовши, ви погоджуєтесь з правилами сервісу',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 🔁 Перемикач режиму
                              TextButton(
                                onPressed: _loading || _gLoading ? null : _toggleMode,
                                child: Text(
                                  _isRegisterMode
                                      ? 'Вже маєте акаунт? Увійти'
                                      : 'Немає акаунту? Зареєструватися',
                                ),
                              ),

                              // 👤 Продовжити як гість
                              TextButton(
                                onPressed: _loading || _gLoading ? null : _continueAsGuest,
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
              ),

              // 🛡️ Глобальний блокуючий оверлей завжди поверх (чітка індикація «чекаємо» після вибору Google-акаунту)
              _BlockingLoader(
                visible: isBlocking,
                label: _progressText ?? 'Зачекайте…',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Приватний віджет повноекранного індикатора.
/// - блокує будь-які торкання під собою;
/// - має напівпрозорий фон і легкий блюр, щоб було видно контекст;
/// - відображає Lottie-лоадер + зрозумілий текст етапу.
class _BlockingLoader extends StatelessWidget {
  final bool visible;
  final String label;

  const _BlockingLoader({
    required this.visible,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return IgnorePointer(
      ignoring: false, // блокуємо взаємодію з тим, що під оверлеєм
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: 1.0,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          // Напівпрозора підкладка
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: theme.colorScheme.surface.withOpacity(0.45)),
              // Легкий блюр для приємного візуального ефекту
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: const SizedBox.expand(),
              ),
              // Контент лоадера
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Lottie-індикатор вашого проєкту
                          const SizedBox(
                            width: 56,
                            height: 56,
                            child: LoadingIndicator(size: 56),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Це може тривати декілька секунд.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
