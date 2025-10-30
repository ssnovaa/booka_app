// lib/screens/reward_test_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/ads/rewarded_ad_service.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart'; // ⬅️ для enableAdsMode()

// UI
import 'package:booka_app/core/ui/reward_confirm_dialog.dart';
import 'package:booka_app/widgets/minutes_counter.dart';

class RewardTestScreen extends StatefulWidget {
  const RewardTestScreen({super.key});
  @override
  State<RewardTestScreen> createState() => _RewardTestScreenState();
}

class _RewardTestScreenState extends State<RewardTestScreen> {
  late final Dio _dio;
  RewardedAdService? _svc;

  // Общие флаги/состояния
  bool _loading = false; // загрузка rewarded-рекламы
  bool _enablingAdsMode = false; // включение ad-mode
  String _status =
      'Ваші хвилини прослуховування закінчилися.\n\n'
      'Можна:\n'
      '• Отримати +15 хв за перегляд винагородної реклами, або\n'
      '• Продовжити з періодичною рекламою (без нарахування хвилин).';

  bool _isAuthorized = false;
  int _userId = 0;

  // Пульс для лічильника хвилин
  final MinutesCounterController _mc = MinutesCounterController();

  @override
  void initState() {
    super.initState();

    _dio = ApiClient.i();

    try {
      final user = context.read<UserNotifier>().user;
      _userId = user?.id ?? 0;
      _isAuthorized = _userId > 0;
    } catch (_) {
      _userId = 0;
      _isAuthorized = false;
    }

    _svc = RewardedAdService(dio: _dio, userId: _userId);
    // (опционально) префетч: _svc!.load();
  }

  // ====== СТАРЫЙ ФЛОУ (сохранён): +15 хв за винагородну рекламу ======
  Future<void> _get15() async {
    if (_svc == null || _loading) return;

    setState(() {
      _loading = true;
      _status = _isAuthorized
          ? 'Завантажую рекламу...'
          : 'Реклама без нагороди (увійдіть, щоб отримувати хвилини)';
    });

    try {
      // 1) Завантаження
      debugPrint('[REWARD] STEP 1: load()');
      final loaded = await _svc!.load();
      debugPrint('[REWARD] loaded=$loaded');
      if (!loaded) {
        final err = _svc?.lastError ??
            'Реклама недоступна (load=false). Спробуйте пізніше.';
        setState(() {
          _loading = false;
          _status = err;
        });
        return;
      }

      setState(() => _status = 'Показую рекламу...');
      // 2) Показ + очікування підтвердження з сервера
      debugPrint('[REWARD] STEP 2: showAndAwaitCredit()');
      final credited = await _svc!.showAndAwaitCredit();
      debugPrint('[REWARD] credited=$credited');

      if (!mounted) return;

      // 3) Обробка результату
      if (credited && _isAuthorized) {
        // Подтверждение
        await showRewardConfirmDialog(
          context,
          title: '+15 хв нараховано',
          subtitle: 'Дякуємо за перегляд реклами',
          autoClose: const Duration(seconds: 7),
        );

        // Обновляем минуты с сервера (никаких локальных инкрементов)
        debugPrint('[REWARD] STEP 3: refreshMinutesFromServer()');
        try {
          await context.read<UserNotifier>().refreshMinutesFromServer();
        } catch (e) {
          debugPrint('[REWARD][WARN] refreshMinutesFromServer() failed: $e');
        }

        // ------------------- 👇 [ВИПРАВЛЕННЯ] 👇 -------------------
        //
        // Повідомляємо AudioPlayerProvider, що баланс,
        // ймовірно, оновився. Він перевірить наявність хвилин
        // і скасує AdMode / таймер, якщо хвилини є.
        //
        debugPrint('[REWARD] STEP 4: Poking AudioPlayerProvider to re-check balance');
        try {
          context.read<AudioPlayerProvider>().rearmFreeSecondsTickerSafely();
        } catch (e) {
          debugPrint('[REWARD][WARN] Failed to poke AudioPlayerProvider: $e');
        }
        // ------------------- 👆 [КІНЕЦЬ ВИПРАВЛЕННЯ] 👆 -------------------

        _mc.pulse();
        setState(() => _status = 'Нараховано +15 хв ✅');
      } else if (credited && !_isAuthorized) {
        setState(() {
          _status =
          'Гість: нагорода не нараховується. Увійдіть, щоб отримувати хвилини.';
        });
      } else {
        final err = _svc?.lastError ??
            'Не вдалося отримати нагороду (credited=false). Перевірте prepare/status у логах.';
        setState(() {
          _status = err;
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[REWARD][ERROR] $e');
      setState(() => _status = 'Помилка показу реклами: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
      // (опционально) префетч: _svc!.load();
    }
  }

  // ====== НОВЫЙ ФЛОУ: согласие на ad-mode (реклама каждые ~10 мин, без нарахувань) ======
  Future<void> _continueWithAds() async {
    if (_enablingAdsMode) return;
    setState(() {
      _enablingAdsMode = true;
      _status = 'Увімкнення режиму з рекламою...';
    });

    try {
      // Включаем ad-mode в аудиопровайдере:
      //  - отключает списание секунд
      //  - даёт плееру играть дальше
      //  - запускает автоматический показ межстраничной рекламы ~ каждые 10 минут (без нарахувань)
      await context.read<AudioPlayerProvider>().enableAdsMode();

      if (!mounted) return;

      _mc.pulse();
      // Экран показывается один раз — закрываем с успехом
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Не вдалося увімкнути режим із рекламою: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _enablingAdsMode = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Глобальный баланс минут
    final minutes = context.watch<UserNotifier>().minutes;

    return Scaffold(
      appBar: AppBar(title: const Text('Продовжити прослуховування')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Статус/описание
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(_status, textAlign: TextAlign.center),
              ),

              const SizedBox(height: 12),

              // Баланс хвилин с «пульсом»
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Баланс: ', style: TextStyle(fontSize: 16)),
                  MinutesCounter(minutes: minutes, controller: _mc),
                ],
              ),

              const SizedBox(height: 20),

              // Кнопка 1 — НОВЫЙ флоу: продолжить с рекламой (ad-mode)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _enablingAdsMode ? null : _continueWithAds,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Продовжити з рекламою (без нарахувань)',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Кнопка 2 — СТАРЫЙ флоу: получить +15 хв за рекламу (rewarded)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : _get15,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _isAuthorized
                          ? 'Отримати +15 хв за рекламу'
                          : 'Подивитись винагородну рекламу (без нарахувань для гостя)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Отмена
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Скасувати'),
              ),

              const SizedBox(height: 8),
              Opacity(
                opacity: 0.7,
                child: Text(
                  'У режимі реклами міжсторінкова реклама показуватиметься приблизно кожні 10 хвилин і закриватиметься автоматично.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}