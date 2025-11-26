import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:booka_app/core/billing/billing_models.dart';
import 'package:booka_app/core/network/api_client.dart';

/// Сервис работы з Google Play Billing через in_app_purchase.
/// - Сам НЕ є ChangeNotifier (стан для UI тримає BillingController)
/// - Умеет:
///   * инициализировать поток покупок
///   * запрашивать продукты
///   * запускать покупку
///   * восстанавливать покупки
///   * дергать бекенд для verify + acknowledge
class BillingService {
  BillingService();

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _initialized = false;

  /// Колбэк, который вызывается после успешной верификации покупки
  /// (например, чтобы обновить пользователя/кредиты снаружи).
  Future<void> Function()? onUserBecamePremium;

  /// Колбэк, который слушает смену состояний покупки
  /// (контроллер подписывается сюда).
  void Function(BillingPurchaseState state, {BillingError? error})?
  onPurchaseStateChange;

  // ---------------------------------------------------------------------------
  // ВНУТРЕННЯЯ ПРОВЕРКА ДОСТУПНОСТИ
  // ---------------------------------------------------------------------------

  /// Каждый раз перед обращением к BillingClient проверяем,
  /// что Google Play Billing доступен.
  Future<void> _ensureAvailable() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        debugPrint('Billing: _ensureAvailable: Not available (in_app_purchase.isAvailable() is false)');
        throw PlatformException(
          code: 'UNAVAILABLE',
          message: 'Google Play Billing недоступний. Спробуйте пізніше.',
        );
      }
      debugPrint('Billing: _ensureAvailable: Available');
    } on PlatformException {
      // пробрасываем как есть, чтобы наверху можно было показать текст
      rethrow;
    } catch (e, st) {
      debugPrint('Billing: _ensureAvailable() error: $e\n$st');
      throw PlatformException(
        code: 'UNAVAILABLE',
        message: 'Не вдалося підʼєднатися до Google Play Billing: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ІНІЦІАЛІЗАЦІЯ / DISPOSE
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    // 🚨 ИЗМЕНЕНИЕ: Если уже инициализирован, сначала полностью сбрасываем состояние.
    if (_initialized) {
      debugPrint('Billing: Init called, but already initialized. Forcing dispose/reconnect.');
      await dispose(resetInitialization: false);
    }

    debugPrint('Billing: Init started...');

    // 1) убеждаемся, что BillingClient живой
    await _ensureAvailable();

    // 2) подписываемся на стрим покупок
    _purchaseSub ??=
        _iap.purchaseStream.listen(_onPurchaseUpdated, onError: _onPurchaseError);

    _initialized = true;
    debugPrint('Billing: Init completed successfully.');
  }

  Future<void> dispose({bool resetInitialization = true}) async {
    debugPrint('Billing: Disposing...');
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    if (resetInitialization) {
      _initialized = false;
    }
  }

  // ---------------------------------------------------------------------------
  // РАБОТА С ПРОДУКТАМИ
  // ---------------------------------------------------------------------------

  Future<List<ProductDetails>> queryProducts(Set<String> productIds) async {
    debugPrint('Billing: Querying products: $productIds');
    // перед запросом к магазину ещё раз проверяем доступность
    await _ensureAvailable();

    final response = await _iap.queryProductDetails(productIds);

    if (response.error != null) {
      debugPrint('Billing: Query error: ${response.error!.message}');
      throw PlatformException(
        code: response.error!.code,
        message: response.error!.message,
      );
    }

    debugPrint('Billing: Query successful. Found: ${response.productDetails.length}, Not Found: ${response.notFoundIDs.length}');

    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      throw PlatformException(
        code: 'NOT_FOUND',
        message: 'Продукт не знайдено у магазині',
      );
    }

    return response.productDetails;
  }

  // ---------------------------------------------------------------------------
  // ПОКУПКА / ВОССТАНОВЛЕНИЕ
  // ---------------------------------------------------------------------------

  Future<void> buy(ProductDetails product) async {
    debugPrint('Billing: Initiating purchase for ${product.id}');
    await _ensureAvailable();

    final param = PurchaseParam(productDetails: product);
    try {
      await _iap.buyNonConsumable(purchaseParam: param);
      debugPrint('Billing: buyNonConsumable called successfully.');
    } on PlatformException catch (e) {
      debugPrint('Billing: buyNonConsumable PlatformException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e, st) {
      debugPrint('Billing: buyNonConsumable Generic Error: $e\n$st');
      rethrow;
    }
  }

  Future<void> restorePurchases() async {
    debugPrint('Billing: Initiating restorePurchases');
    await _ensureAvailable();

    await _iap.restorePurchases();
  }

  // ---------------------------------------------------------------------------
  // ОБРАБОТКА СТРИМА ПОКУПОК
  // ---------------------------------------------------------------------------

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    debugPrint('Billing: _onPurchaseUpdated received ${purchases.length} purchases.');

    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          onPurchaseStateChange?.call(BillingPurchaseState.purchasing);
          break;

        case PurchaseStatus.error:
          String friendlyMessage = 'Помилка оплати';
          final error = purchase.error;
          final rawMessage = error?.message ?? '';
          final rawCode = error?.code;

          // 🚨 ИЗМЕНЕНИЕ: Обработка специфической ошибки BillingUnavailable (код 3)
          if (rawCode == 'purchase_error' && rawMessage.contains('billingUnavailable')) {
            friendlyMessage = 'Помилка оплати. Не вдалося зв\'язатися з Google Play. Перевірте, чи оновлені ваші Google Play Services, або спробуйте пізніше.';
          } else {
            // Используем стандартное сообщение, если это не известная специфическая ошибка
            friendlyMessage = 'Помилка оплати. Спробуйте ще раз.';
          }


          debugPrint('Billing: Purchase error details: ${rawCode ?? 'N/A'} - ${rawMessage}');

          onPurchaseStateChange?.call(
            BillingPurchaseState.error,
            error: BillingError(
              message: friendlyMessage, // ⬅️ Используем дружественное сообщение
              raw: purchase.error,
            ),
          );
          break;

        case PurchaseStatus.canceled:
          debugPrint('Billing: Purchase canceled by user.');
          onPurchaseStateChange?.call(BillingPurchaseState.none);
          break;

        case PurchaseStatus.purchased:
          debugPrint('Billing: Purchase successful. Verifying...');
          await _verifyAndCompletePurchase(purchase);
          break;

        case PurchaseStatus.restored:
          debugPrint('Billing: Purchase restored. Verifying...');
          onPurchaseStateChange?.call(BillingPurchaseState.restoring);
          await _verifyAndCompletePurchase(purchase);
          break;
      }
    }
  }

  void _onPurchaseError(Object error) {
    debugPrint('Billing: purchaseStream Error: $error');
    onPurchaseStateChange?.call(
      BillingPurchaseState.error,
      error: BillingError(message: 'Помилка оплати', raw: error),
    );
  }

  // ---------------------------------------------------------------------------
  // ВЕРИФИКАЦИЯ / ACKNOWLEDGE
  // ---------------------------------------------------------------------------

  Future<void> _verifyAndCompletePurchase(PurchaseDetails purchase) async {
    try {
      final token = purchase.verificationData.serverVerificationData;
      debugPrint('Billing: Sending token to server for verification: ${purchase.productID}');

      await ApiClient.i().post('/subscriptions/play/verify', data: {
        'purchaseToken': token,
        'productId': purchase.productID,
      });

      debugPrint('Billing: Server verification successful.');

      onPurchaseStateChange?.call(BillingPurchaseState.purchased);
      await onUserBecamePremium?.call();
    } catch (e, st) {
      debugPrint('Billing: verification error: $e\n$st');
      onPurchaseStateChange?.call(
        BillingPurchaseState.error,
        error: BillingError(
          message: 'Підтвердження покупки не вдалося',
          raw: e,
        ),
      );
    } finally {
      if (purchase.pendingCompletePurchase) {
        try {
          debugPrint('Billing: Completing purchase...');
          await _iap.completePurchase(purchase);
          debugPrint('Billing: Purchase completed successfully.');
        } catch (e) {
          debugPrint('Billing: completePurchase error: $e');
        }
      }
    }
  }
}