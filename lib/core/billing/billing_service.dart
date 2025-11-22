import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:booka_app/core/billing/billing_models.dart';
import 'package:booka_app/core/network/api_client.dart';

class BillingService {
  BillingService._();

  static final BillingService I = BillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;

  static bool _pendingPurchasesEnabled = false;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _initialized = false;

  Future<void> Function()? onUserBecamePremium;
  void Function(BillingPurchaseState state, {BillingError? error})?
      onPurchaseStateChange;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _enablePendingPurchasesIfNeeded();

    final available = await _iap.isAvailable();
    if (!available) {
      _initialized = false;
      throw PlatformException(
        code: 'UNAVAILABLE',
        message: 'Google Play Billing недоступний',
      );
    }

    _purchaseSub ??=
        _iap.purchaseStream.listen(_onPurchaseUpdated, onError: _onPurchaseError);
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialized = false;
  }

  Future<List<ProductDetails>> queryProducts(Set<String> productIds) async {
    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      throw PlatformException(
        code: response.error!.code,
        message: response.error!.message,
      );
    }

    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      throw PlatformException(
        code: 'NOT_FOUND',
        message: 'Продукт не знайдено у магазині',
      );
    }

    return response.productDetails;
  }

  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          onPurchaseStateChange?.call(BillingPurchaseState.purchasing);
          break;
        case PurchaseStatus.error:
          onPurchaseStateChange?.call(
            BillingPurchaseState.error,
            error: BillingError(
              message: purchase.error?.message ?? 'Помилка оплати',
              raw: purchase.error,
            ),
          );
          break;
        case PurchaseStatus.canceled:
          onPurchaseStateChange?.call(BillingPurchaseState.none);
          break;
        case PurchaseStatus.purchased:
          await _verifyAndCompletePurchase(purchase);
          break;
        case PurchaseStatus.restored:
          onPurchaseStateChange?.call(BillingPurchaseState.restoring);
          await _verifyAndCompletePurchase(purchase);
          break;
      }
    }
  }

  void _onPurchaseError(Object error) {
    onPurchaseStateChange?.call(
      BillingPurchaseState.error,
      error: BillingError(message: 'Помилка оплати', raw: error),
    );
  }

  Future<void> _verifyAndCompletePurchase(PurchaseDetails purchase) async {
    try {
      final token = purchase.verificationData.serverVerificationData;
      await ApiClient.i().post('/subscriptions/play/verify', data: {
        'purchaseToken': token,
        'productId': purchase.productID,
      });

      onPurchaseStateChange?.call(BillingPurchaseState.purchased);
      await onUserBecamePremium?.call();
    } catch (e, st) {
      debugPrint('Billing: verification error: $e\n$st');
      onPurchaseStateChange?.call(
        BillingPurchaseState.error,
        error: BillingError(message: 'Підтвердження покупки не вдалося', raw: e),
      );
    } finally {
      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (e) {
          debugPrint('Billing: completePurchase error: $e');
        }
      }
    }
  }

  void _enablePendingPurchasesIfNeeded() {
    if (_pendingPurchasesEnabled) return;
    try {
      _iap.enablePendingPurchases();
      _pendingPurchasesEnabled = true;
    } catch (e) {
      debugPrint('Billing: enablePendingPurchases failed: $e');
    }
  }
}
