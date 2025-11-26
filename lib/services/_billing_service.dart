// lib/services/_billing_service.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/models/user.dart' show getUserType;
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';

/// Сервис работы с подпиской через in_app_purchase.
///
/// Делает ровно то, что рекомендуют авторы плагина:
/// - один глобальный InAppPurchase.instance;
/// - один глобальный purchaseStream;
/// - перед использованием магазина: isAvailable() + queryProductDetails();
/// - при клике "купить" — buyNonConsumable в try/catch.
///
/// ДОПОЛНИТЕЛЬНО:
/// - в buySubscription *всегда* вызываем isAvailable(), даже если ProductDetails уже есть.
///   Это лечит кейс `PlatformException(UNAVAILABLE, BillingClient is unset. Try reconnecting., ...)`
///   после возврата в приложение / пересоздания Activity.
class BillingService extends ChangeNotifier {
  /// Идентификатор товара в Google Play (должен совпадать с Play Console).
  static const String kProductId = 'booka_premium_month';

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _isQuerying = false;
  bool _isBuying = false;
  String? _error;

  bool _disposed = false;

  /// Контекст приложения, чтобы достать UserNotifier и AudioPlayerProvider.
  /// Передаётся один раз сверху (см. main.dart → attachContext).
  BuildContext? _appContext;

  BillingService() {
    debugPrint('BillingService: constructor');

    // Официальный паттерн: один глобальный listener purchaseStream
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e, StackTrace st) {
        debugPrint('BillingService: purchaseStream error: $e\n$st');
        _error = 'Помилка оплати. Спробуйте ще раз.';
        _notify();
      },
    );

    // Небольшая отложенная инициализация, как в примерах.
    scheduleMicrotask(_bootstrap);
  }

  /// Привязка BuildContext, чтобы можно было обновлять UserNotifier/AudioPlayerProvider.
  void attachContext(BuildContext context) {
    _appContext = context;
  }

  // === Публичные геттеры для UI ===

  ProductDetails? get product => _product;

  bool get isQuerying => _isQuerying;

  bool get isBuying => _isBuying;

  String? get error => _error;

  bool get hasProduct => _product != null;

  @override
  void dispose() {
    debugPrint('BillingService: dispose');
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // === Стартовая инициализация ===

  Future<void> _bootstrap() async {
    debugPrint('BillingService: bootstrap start');

    if (Platform.isAndroid) {
      // Чуть подождём, чтобы плагин корректно привязался к Activity.
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await ensureProductLoaded();

    // Как в официалке — один restorePurchases на старте.
    try {
      debugPrint('BillingService: restorePurchases() on bootstrap');
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('BillingService: restorePurchases error on bootstrap: $e');
    }

    debugPrint('BillingService: bootstrap done');
  }

  /// Обеспечить загрузку ProductDetails.
  ///
  /// Паттерн как в примере:
  /// - проверяем isAvailable();
  /// - если ок — queryProductDetails;
  /// - если нет — выставляем error и даём UI кнопку "Оновити".
  Future<void> ensureProductLoaded() async {
    if (_product != null) return;

    _isQuerying = true;
    _error = null;
    _notify();

    try {
      final bool isAvailable = await _iap.isAvailable();
      debugPrint('BillingService: isAvailable() = $isAvailable');

      if (!isAvailable) {
        _isQuerying = false;
        _error =
        'Google Play недоступний. Перевірте інтернет або спробуйте пізніше.';
        _notify();
        return;
      }

      final response = await _iap.queryProductDetails({kProductId});
      debugPrint(
        'BillingService: queryProductDetails -> '
            'notFoundIDs=${response.notFoundIDs}, products=${response.productDetails.length}',
      );

      if (response.notFoundIDs.isNotEmpty ||
          response.productDetails.isEmpty) {
        _isQuerying = false;
        _error =
        'Підписка недоступна. Спробуйте оновити або перевірте Play Market.';
        _notify();
        return;
      }

      _product = response.productDetails.first;
      _isQuerying = false;
      _notify();
    } on PlatformException catch (e, st) {
      debugPrint('BillingService: ensureProductLoaded PlatformException: $e\n$st');
      _isQuerying = false;
      _error = kDebugMode
          ? 'Помилка завантаження підписки: ${e.message}'
          : 'Не вдалося завантажити підписку. Спробуйте пізніше.';
      _notify();
    } catch (e, st) {
      debugPrint('BillingService: ensureProductLoaded error: $e\n$st');
      _isQuerying = false;
      _error =
      'Не вдалося завантажити підписку. Спробуйте пізніше.';
      _notify();
    }
  }

  /// Ручное обновление информации о продукте (кнопка "Оновити").
  Future<void> reloadProduct() async {
    // Сбрасываем кэш продукта и пробуем загрузить заново.
    _product = null;
    await ensureProductLoaded();
  }

  /// Вызов restorePurchases по кнопке "Відновити покупку".
  Future<void> restorePurchases() async {
    try {
      debugPrint('BillingService: restorePurchases() from UI');
      await _iap.restorePurchases();
    } catch (e, st) {
      debugPrint('BillingService: restorePurchases() error from UI: $e\n$st');
      // Ошибку в UI можно не показывать — у пользователя и так есть кнопка "Оновити".
    }
  }

  /// Запуск покупки подписки.
  ///
  /// Логика:
  /// - ВСЕГДА перед покупкой вызываем isAvailable() — даже если ProductDetails уже закэширован;
  /// - при необходимости подгружаем продукт через ensureProductLoaded();
  /// - buyNonConsumable обёрнут в try/catch;
  /// - при UNAVAILABLE мягко показываем ошибку и тихо делаем reloadProduct().
  Future<void> buySubscription({BuildContext? context}) async {
    _isBuying = true;
    _error = null;
    _notify();

    try {
      // 1) Явная проверка доступности магазина — каждый раз перед покупкой.
      final bool isAvailable = await _iap.isAvailable();
      debugPrint('BillingService: buySubscription isAvailable() = $isAvailable');

      if (!isAvailable) {
        _isBuying = false;
        _error =
        'Google Play недоступний. Перевірте інтернет або спробуйте пізніше.';
        _notify();
        return;
      }

      // 2) Убеждаемся, что продукт загружен.
      if (_product == null) {
        await ensureProductLoaded();
      }

      if (_product == null) {
        // ensureProductLoaded уже выставил _error, просто выходим.
        _isBuying = false;
        _notify();
        return;
      }

      debugPrint('BillingService: buy for ${_product!.id}');
      final param = PurchaseParam(productDetails: _product!);
      await _iap.buyNonConsumable(purchaseParam: param);
      // _isBuying дальше сбросится в _onPurchases (pending/purchased/canceled).
    } on PlatformException catch (e, st) {
      debugPrint('BillingService: buy PlatformException -> $e\n$st');
      _isBuying = false;

      if (e.code == 'UNAVAILABLE') {
        // Именно тот кейс, который ты ловишь в логах: BillingClient is unset.
        _error = 'Не вдалося запустити оплату. Спробуйте ще раз.';
        _notify();

        // Мягкий «рестарт» биллинга: при следующем клике мы снова пройдем
        // isAvailable() + ensureProductLoaded().
        unawaited(reloadProduct());
      } else {
        _error = 'Не вдалося запустити оплату. Спробуйте ще раз.';
        _notify();
      }
    } catch (e, st) {
      debugPrint('BillingService: buy error -> $e\n$st');
      _isBuying = false;
      _error = 'Не вдалося запустити оплату. Спробуйте ще раз.';
      _notify();
    }
  }

  // === Поллинг статуса "isPaid" после покупки ===

  Future<void> _pollPaidStatus() async {
    final ctx = _appContext;
    if (ctx == null) {
      debugPrint(
        'BillingService: _pollPaidStatus called but _appContext is null',
      );
      return;
    }

    final userNotifier = ctx.read<UserNotifier>();

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 2));
      await userNotifier.refreshUserFromMe();
      debugPrint('BillingService: poll paid? -> ${userNotifier.isPaidNow}');
      if (_disposed) return;
      if (userNotifier.isPaidNow) {
        final user = userNotifier.user;
        if (user != null) {
          final audio = ctx.read<AudioPlayerProvider>();
          audio.userType = getUserType(user);
          audio.notifyListeners();
        }

        _notify();
        return;
      }
    }
  }

  // === Обработка purchaseStream ===

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      debugPrint(
        'BillingService: purchase event -> '
            'id=${p.productID} status=${p.status} pending=${p.pendingCompletePurchase}',
      );

      if (_disposed) return;

      if (p.status == PurchaseStatus.pending) {
        _isBuying = true;
        _notify();
      } else if (p.status == PurchaseStatus.error) {
        debugPrint('BillingService: purchase error -> ${p.error}');
        _isBuying = false;
        _error = 'Помилка: ${p.error?.message ?? "Unknown error"}';
        _notify();

        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final token = p.verificationData.serverVerificationData;
        final short =
        token.isNotEmpty ? token.substring(0, token.length.clamp(0, 12)) : '';
        debugPrint(
          'BillingService: purchased/restored, sending verify token=$short...',
        );

        try {
          await ApiClient.i().post('/subscriptions/play/verify', data: {
            'purchaseToken': token,
            'productId': kProductId,
          });

          final ctx = _appContext;
          if (ctx != null) {
            debugPrint(
              'BillingService: refresh user from /auth/me (immediate)',
            );
            final userNotifier = ctx.read<UserNotifier>();
            await userNotifier.refreshUserFromMe();

            final user = userNotifier.user;
            if (user != null) {
              final audio = ctx.read<AudioPlayerProvider>();
              audio.userType = getUserType(user);
              audio.notifyListeners();
            }

            // На случай, если /auth/me задержался.
            unawaited(_pollPaidStatus());
          } else {
            debugPrint(
              'BillingService: no _appContext, skip immediate user refresh',
            );
          }

          if (p.pendingCompletePurchase) {
            debugPrint('BillingService: completing purchase (acknowledge)');
            await _iap.completePurchase(p);
          }

          _isBuying = false;
          _error = null;
          _notify();
        } catch (e, st) {
          debugPrint('BillingService: verify failed -> $e\n$st');
          _isBuying = false;
          _error =
          'Не вдалося підтвердити покупку на сервері. Спробуйте оновити екран.';
          _notify();
        }
      } else if (p.status == PurchaseStatus.canceled) {
        debugPrint('BillingService: purchase canceled');
        _isBuying = false;
        _error = null;
        _notify();

        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }
    }
  }
}
