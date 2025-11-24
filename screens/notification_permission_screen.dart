// lib/screens/notification_permission_screen.dart
import 'package:flutter/material.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/core/permissions/notification_permission.dart';

/// Адаптивний екран запиту дозволу на сповіщення.
/// Усі тексти українською, без скорочень.
class NotificationPermissionScreen extends StatefulWidget {
  /// Дія, яка викликається, якщо користувач надав дозвіл.
  final VoidCallback? onGranted;

  /// Дія, яка викликається, якщо користувач відмовився або відклав рішення.
  final VoidCallback? onSkip;

  const NotificationPermissionScreen({
    super.key,
    this.onGranted,
    this.onSkip,
  });

  @override
  State<NotificationPermissionScreen> createState() => _NotificationPermissionScreenState();
}

class _NotificationPermissionScreenState extends State<NotificationPermissionScreen> {
  bool _processing = false;
  NotificationPermissionState _state = NotificationPermissionState.unknown;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await NotificationPermissionService.getStatus();
    if (!mounted) return;
    setState(() => _state = s);
  }

  Future<void> _request() async {
    setState(() => _processing = true);
    final s = await NotificationPermissionService.request();
    if (!mounted) return;
    setState(() {
      _state = s;
      _processing = false;
    });

    // ✅ Враховуємо iOS "provisional" як успішний дозвіл
    if (s == NotificationPermissionState.granted ||
        s == NotificationPermissionState.provisional) {
      widget.onGranted?.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  Future<void> _openSettings() async {
    await NotificationPermissionService.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final cs = theme.colorScheme;

    // Обмежуємо масштаб шрифтів, щоб верстка не ламалася на дуже великих налаштуваннях
    final clamped = media.textScaleFactor.clamp(1.0, 1.35);

    final bool showSettingsHint =
        _state == NotificationPermissionState.permanentlyDenied ||
            _state == NotificationPermissionState.restricted;

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: MediaQuery(
        data: media.copyWith(textScaleFactor: clamped),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Іконка і заголовок
                    Container(
                      width: 96,
                      height: 96,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            cs.primaryContainer.withOpacity(0.9),
                            cs.primary.withOpacity(0.9),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 20,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.notifications_active_rounded, size: 44, color: Colors.white),
                    ),
                    Text(
                      'Дозвольте нам надсилати корисні сповіщення',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ми надішлемо лише важливе: вихід нових глав, нагадування про прослуховування та персональні рекомендації. '
                          'Ви завжди можете змінити налаштування у будь-який момент.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: cs.onSurface.withOpacity(0.85)),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 18),

                    // Переваги у вигляді пунктів
                    _BenefitRow(
                      icon: Icons.new_releases_rounded,
                      text: 'Повідомлення про вихід нових розділів та книг.',
                    ),
                    const SizedBox(height: 10),
                    _BenefitRow(
                      icon: Icons.schedule_rounded,
                      text: 'Нагадування продовжити прослуховування з того місця, де ви зупинилися.',
                    ),
                    const SizedBox(height: 10),
                    _BenefitRow(
                      icon: Icons.star_rounded,
                      text: 'Персональні рекомендації відповідно до ваших уподобань.',
                    ),

                    const SizedBox(height: 24),

                    // Основна кнопка
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _processing ? null : _request,
                        child: _processing
                            ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Text('Дозволити сповіщення'),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Альтернатива: "Пізніше"
                    TextButton(
                      onPressed: _processing
                          ? null
                          : () {
                        widget.onSkip?.call();
                        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                      },
                      child: const Text('Пізніше'),
                    ),

                    if (showSettingsHint) ...[
                      const SizedBox(height: 8),
                      // Підказка якщо доступ заборонено назавжди
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Сповіщення вимкнено у налаштуваннях пристрою', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            Text(
                              'Щоб увімкнути сповіщення, відкрийте системні налаштування застосунку та надайте доступ.',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.8)),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _openSettings,
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('Відкрити налаштування'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    // Примітка щодо політики
                    Text(
                      'Ми поважаємо вашу приватність. Частоту і тип сповіщень можна коригувати у налаштуваннях застосунку.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                      textAlign: TextAlign.center,
                    ),
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

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}
