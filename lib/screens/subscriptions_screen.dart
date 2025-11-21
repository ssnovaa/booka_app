// lib/screens/subscriptions_screen.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/models/user.dart' show UserType, getUserType;
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Підписки',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
            ),
            const SizedBox(height: 6),
            Text(
              'Оберіть підписку, щоб відкрити весь каталог і слухати без обмежень.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const SubscriptionSection(),
          ],
        ),
      ),
    );
  }
}

class SubscriptionSection extends StatefulWidget {
  const SubscriptionSection({super.key});

  @override
  State<SubscriptionSection> createState() => _SubscriptionSectionState();
}

class _SubscriptionSectionState extends State<SubscriptionSection> {
  static const String kProductId = 'booka_premium_month'; // ← ID в Play Console
  static const int _maxBillingReconnectAttempts = 3;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _isQuerying = false;
  bool _isBuying = false;
  String? _error;

  // 👇 новый флаг, чтобы не дёргать реинициализацию параллельно
  bool _isReconnectingBilling = false;
  // 👇 флаг автоповтора после "BillingClient is unset"
  bool _isAutoReloadingBilling = false;
  // 👇 блокировка, чтобы не крутиться в retry-цикле, пока не закінчиться реініт
  bool _stopRetriesUntilReinitCompletes = false;
  // 👇 лічильник послідовних невдалих реінітів BillingClient
  int _failedReinitAttempts = 0;
  bool _restoreInFlight = false;
  bool _restoreSpinner = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
        'Billing: SubscriptionSection init, product=$kProductId, platform=${Platform.isAndroid ? "android" : "other"}');

    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e, st) {
      debugPrint('Billing: stream error: $e');
      if (mounted) {
        setState(() => _error = 'Помилка оплати. Спробуйте ще раз.');
      }
    });

    // ‼️ Викликаємо ініціалізацію з невеликою затримкою, щоб дати Flutter час стабілізуватися
    // Це часто вирішує проблему "not found" при швидкому переході
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Маленька затримка для Android (InAppPurchasePlugin іноді потребує часу)
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _failedReinitAttempts = 0; // скидаємо лічильник при старті
    // ‼️ Викликаємо обгортку з повторними спробами
    await _queryProductWithRetry();

    await _restorePurchasesSafely(reason: 'bootstrap');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _restoreFromUi() async {
    setState(() {
      _error = null;
      _restoreSpinner = true;
    });

    await _restorePurchasesSafely(reason: 'manual');

    if (mounted) {
      setState(() {
        _restoreSpinner = false;
      });
    }
  }

  /// 🔄 Реинициализация BillingClient при "BillingClient is unset"
  Future<void> _tryReinitBillingClient() async {
    if (_isReconnectingBilling) {
      debugPrint('Billing: [reinit] already in progress, skip');
      return;
    }

    if (_failedReinitAttempts >= _maxBillingReconnectAttempts) {
      debugPrint('Billing: [reinit] max attempts reached, skip further reinit');
      return;
    }

    _isReconnectingBilling = true;
    debugPrint('Billing: [reinit] start re-init flow (like on app start)');

    try {
      if (Platform.isAndroid) {
        debugPrint(
            'Billing: [reinit] Android, small delay before restorePurchases');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await _restorePurchasesSafely(reason: 'reinit');
    } catch (e, st) {
      debugPrint('Billing: [reinit] restorePurchases error: $e\n$st');
    } finally {
      _isReconnectingBilling = false;
      debugPrint('Billing: [reinit] done');
    }
  }

  // ‼️ ОБГОРТКА: кілька спроб підключення/запиту ‼️
  Future<void> _queryProductWithRetry() async {
    if (_stopRetriesUntilReinitCompletes) {
      // вже очікуємо автоперезапуск після reinit — нові спроби не робимо
      return;
    }

    const maxRetries = 5; // Збільшено до 5, щоб впоратися з таймаутами
    int attempt = 0;

    while (attempt < maxRetries && mounted) {
      attempt++;
      final ok = await _queryProduct();
      if (ok) return; // успіх — виходимо

      if (_stopRetriesUntilReinitCompletes) {
        // якщо під час запиту побачили BillingClient unset — виходимо із циклу
        return;
      }

      // ❌ продукт не отримали — спробуємо ще через секунду
      if (attempt < maxRetries) {
        debugPrint('Billing: Product not found (Attempt $attempt). Retrying in 1s...');
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Якщо ми тут — усі спроби вичерпано
    if (mounted && _product == null && _error == null) {
      setState(() {
        _error = 'Не вдалося завантажити підписку. Спробуйте пізніше.';
      });
    }
  }

  /// 🔌 ОДИН запит товару
  Future<bool> _queryProduct() async {
    if (_product != null) return true; // вже є

    setState(() {
      _isQuerying = true;
      _error = null;
    });

    try {
      // 1️⃣ Перевіряємо готовність
      final isReady = await _iap.isAvailable();
      debugPrint('Billing: isAvailable() = $isReady');
      if (!isReady) {
        setState(() {
          _error = 'Google Play недоступний. Перевірте інтернет або спробуйте пізніше.';
        });
        _isQuerying = false;
        return false;
      }

      // 2️⃣ Запитуємо один продукт
      debugPrint('Billing: Starting single query for $kProductId...');
      final response = await _iap.queryProductDetails({kProductId});
      debugPrint('Billing: queryProductDetails -> notFoundIDs=${response.notFoundIDs}, products=${response.productDetails.length}');

      if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
        setState(() {
          _error = 'Підписка недоступна. Спробуйте оновити або перевірте Play Market.';
        });
        _isQuerying = false;
        return false;
      }

      setState(() {
        _product = response.productDetails.first;
        _isQuerying = false;
        _failedReinitAttempts = 0; // успішний запит — обнуляємо
      });
      return true;
    } on PlatformException catch (e, st) {
      debugPrint('Billing: _queryProduct PlatformException code=${e.code}, message=${e.message}\n$st');

      // Якщо конкретно сказали, що BillingClient unset — запускаємо реініт і ставимо блокатор повторів
      if (e.code == 'UNAVAILABLE' &&
          e.message != null &&
          e.message!.contains('BillingClient is unset')) {
        _failedReinitAttempts += 1;
        _stopRetriesUntilReinitCompletes = true; // блокуємо нові спроби

        if (_failedReinitAttempts >= _maxBillingReconnectAttempts) {
          if (mounted) {
            setState(() {
              _error =
                  'Google Play Billing не відповідає. Повністю закрийте застосунок і відкрийте знову, щоб продовжити покупку.';
            });
          }
          return false;
        }

        await _tryReinitBillingClient();

        // Якщо реінітів вже декілька і все ще немає зв'язку — просимо перезапуск
        if (mounted) {
          setState(() {
            _error =
                'Google Play Billing перезапускається. Спробуйте ще раз за кілька секунд.';
          });
        }

        if (mounted) {
          await _autoReloadProductAfterReinit();
        }
        return false;
      }

      if (mounted) {
        setState(() {
          _error = kDebugMode
              ? 'Помилка завантаження підписки: ${e.message}'
              : 'Не вдалося завантажити підписку. Спробуйте пізніше.';
        });
      }
      return false;
    } catch (e, st) {
      debugPrint('Billing: _queryProduct unexpected error -> $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Не вдалося завантажити підписку. Спробуйте пізніше.';
        });
      }
      return false;
    }
  }

  /// ⚙️ Автоперезапуск запиту продукту після реініціалізації billing
  Future<void> _autoReloadProductAfterReinit() async {
    if (_isAutoReloadingBilling) {
      debugPrint('Billing: [auto-reload] already scheduled, skip');
      return;
    }
    _isAutoReloadingBilling = true;

    try {
      debugPrint('Billing: [auto-reload] wait 2s and query product again');
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      debugPrint('Billing: [auto-reload] re-run _queryProductWithRetry()');
      _stopRetriesUntilReinitCompletes = false; // після паузи — можна знову пробувати
      await _queryProductWithRetry();
    } finally {
      _isAutoReloadingBilling = false;
      debugPrint('Billing: [auto-reload] done');
    }
  }

  /// ⚠️ "опитування" статусу ПІСЛЯ покупки
  Future<void> _pollPaidStatus() async {
    final userN = context.read<UserNotifier>();
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 2));
      await userN.refreshUserFromMe();
      debugPrint('Billing: poll paid? -> ${userN.isPaidNow}');
      if (!mounted) return;
      if (userN.isPaidNow) {
        // як тільки сервер сказав, що юзер платний —
        // синхронізуємо тип користувача в AudioPlayerProvider,
        // щоб GlobalBannerInjector одразу прибрав рекламу
        final u = userN.user;
        if (u != null) {
          final audio = context.read<AudioPlayerProvider>();
          audio.userType = getUserType(u);
          // 👇 важливо: повідомляємо слухачів (в т.ч. GlobalBannerInjector)
          audio.notifyListeners();
        }

        setState(() {});
        return;
      }
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      debugPrint(
          'Billing: purchase event -> id=${p.productID} status=${p.status} pending=${p.pendingCompletePurchase}');

      if (!mounted) return;

      if (p.status == PurchaseStatus.pending) {
        setState(() => _isBuying = true);
      } else if (p.status == PurchaseStatus.error) {
        debugPrint('Billing: purchase error -> ${p.error}');
        setState(() {
          _isBuying = false;
          _error = 'Помилка: ${p.error?.message ?? "Unknown error"}';
        });
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final token = p.verificationData.serverVerificationData;
        final short =
        token.isNotEmpty ? token.substring(0, token.length.clamp(0, 12)) : '';
        debugPrint(
            'Billing: purchased/restored, sending verify token=$short...');

        try {
          await ApiClient.i().post('/subscriptions/play/verify', data: {
            'purchaseToken': token,
            'productId': kProductId,
          });

          if (mounted) {
            debugPrint('Billing: refresh user from /auth/me (immediate)');
            final userN = context.read<UserNotifier>();
            await userN.refreshUserFromMe();

            // одразу після оновлення профілю синхронізуємо userType в плеєрі
            final u = userN.user;
            if (u != null) {
              final audio = context.read<AudioPlayerProvider>();
              audio.userType = getUserType(u);
              // 👇 тут теж оповіщаємо, щоб банер зник одразу
              audio.notifyListeners();
            }

            // на випадок, якщо /auth/me затримався
            unawaited(_pollPaidStatus());
          }

          if (p.pendingCompletePurchase) {
            debugPrint('Billing: completing purchase (acknowledge)');
            await _iap.completePurchase(p);
          }

          if (mounted) {
            setState(() {
              _isBuying = false;
              _error = null;
            });
          }
        } catch (e, st) {
          debugPrint('Billing: verify failed -> $e\n$st');
          if (mounted) {
            setState(() {
              _isBuying = false;
              _error =
              'Не вдалося підтвердити покупку на сервері. Спробуйте оновити екран.';
            });
          }
        }
      } else if (p.status == PurchaseStatus.canceled) {
        debugPrint('Billing: purchase canceled');
        if (mounted) {
          setState(() {
            _isBuying = false;
            _error = null;
          });
        }
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }
    }
  }

  // ✅ Покупка без offerToken/GooglePlayPurchaseParam
  Future<void> _buy() async {
    final product = _product;
    if (product == null) {
      debugPrint(
          'Billing: _buy() called but _product is null. Retry querying.');
      await _queryProductWithRetry(); // 👈 ВИКЛИКАЄМО НОВИЙ МЕТОД
      if (_product == null) return; // Все ще нуль
    }

    setState(() {
      _isBuying = true;
      _error = null;
    });

    try {
      debugPrint('Billing: buy for ${_product!.id}');
      final param = PurchaseParam(productDetails: _product!);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e, st) {
      debugPrint('Billing: buy error -> $e\n$st');
      if (mounted) {
        setState(() {
          _isBuying = false;
          _error = 'Не вдалося ініціювати покупку: $e';
        });
      }
    }
  }

  Future<void> _restorePurchasesSafely({required String reason}) async {
    if (_restoreInFlight) {
      debugPrint('Billing: [$reason] restore already running, skip');
      return;
    }
    if (_failedReinitAttempts >= _maxBillingReconnectAttempts) {
      debugPrint('Billing: [$reason] restore skipped, max attempts reached');
      return;
    }

    _restoreInFlight = true;
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        debugPrint('Billing: [$reason] restore skipped, billing not available');
        return;
      }

      debugPrint('Billing: [$reason] calling restorePurchases()...');
      await _iap.restorePurchases();
      debugPrint('Billing: [$reason] restorePurchases finished');
      _failedReinitAttempts = 0;
    } on PlatformException catch (e, st) {
      debugPrint('Billing: [$reason] restorePurchases error: $e\n$st');

      final isUnset =
          e.code == 'UNAVAILABLE' && (e.message?.contains('BillingClient is unset') ?? false);
      if (isUnset) {
        _failedReinitAttempts += 1;
        _stopRetriesUntilReinitCompletes = true;

        if (mounted) {
          setState(() {
            _error = _failedReinitAttempts >= _maxBillingReconnectAttempts
                ? 'Google Play Billing не відповідає. Повністю закрийте застосунок і відкрийте знову.'
                : 'Google Play Billing перезапускається. Спробуйте ще раз за кілька секунд.';
          });
        }
      }
    } finally {
      _restoreInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userN = context.watch<UserNotifier>();
    final isPaidNow = userN.isPaidNow;
    debugPrint(
        'Billing: build section, isPaidNow=$isPaidNow, productLoaded=${_product != null}, querying=$_isQuerying, error=$_error');

    if (isPaidNow) {
      final until = userN.user?.paidUntil;
      final subtitle = until != null
          ? 'Активно до: ${until.toLocal().toString().substring(0, 10)}'
          : 'Преміум активний';
      return _CardWrap(
        title: 'Booka Premium',
        child: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    Widget body;
    if (_isQuerying) {
      body = const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Завантаження підписки…'),
        ],
      );
    } else if (_error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: TextStyle(
                color: Theme.of(context).colorScheme.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _queryProductWithRetry,
                child: const Text('Оновити'),
              ),
              OutlinedButton(
                onPressed: _restoreSpinner ? null : _restoreFromUi,
                child: Text(_restoreSpinner ? 'Відновлення…' : 'Відновити'),
              ),
            ],
          ),
        ],
      );
    } else if (_product == null) {
      body = Row(
        children: [
          const Expanded(child: Text('Немає інформації про товар')),
          OutlinedButton(
            onPressed: _queryProductWithRetry,
            child: const Text('Оновити'),
          ),
        ],
      );
    } else {
      final price = _product!.price;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Місячна підписка: $price',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: _isBuying ? null : _buy,
                child: Text(_isBuying ? 'Обробка…' : 'Підключити Premium'),
              ),
              OutlinedButton(
                onPressed: _restoreSpinner ? null : _restoreFromUi,
                child: Text(_restoreSpinner ? 'Відновлення…' : 'Відновити покупку'),
              ),
            ],
          ),
        ],
      );
    }

    return _CardWrap(title: 'Booka Premium', child: body);
  }
}

class _CardWrap extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardWrap({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Theme.of(context)
              .dividerColor
              .withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (Theme.of(context).brightness == Brightness.dark)
                Icon(Icons.workspace_premium,
                    color: Theme.of(context).colorScheme.tertiary),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
