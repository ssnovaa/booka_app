import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:booka_app/core/billing/billing_models.dart';
import 'package:booka_app/core/billing/billing_service.dart';
import 'package:booka_app/models/user.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';

class BillingController extends ChangeNotifier {
  BillingController(
      this._service, {
        required this.userNotifier,
        required this.audioPlayerProvider,
      }) {
    _service.onPurchaseStateChange = _handlePurchaseStateChange;
    _service.onUserBecamePremium = _handleUserBecamePremium;
  }

  final BillingService _service;
  final UserNotifier userNotifier;
  final AudioPlayerProvider audioPlayerProvider;

  BillingStatus status = BillingStatus.idle;
  BillingPurchaseState purchaseState = BillingPurchaseState.none;
  BillingProduct? product;
  BillingError? error;

  ProductDetails? _productDetails;

  static const String _productId = 'booka_premium_month';

  Future<void> init() async {
    try {
      status = BillingStatus.loadingProducts;
      error = null;
      notifyListeners();

      await _service.init();
      await reloadProducts();

      status = BillingStatus.ready;
    } catch (e) {
      status = BillingStatus.error;
      error = BillingError(message: 'Білінг недоступний', raw: e);
    } finally {
      notifyListeners();
    }
  }

  Future<void> reloadProducts() async {
    try {
      status = BillingStatus.loadingProducts;
      error = null;
      notifyListeners();

      final products = await _service.queryProducts({_productId});
      if (products.isNotEmpty) {
        _productDetails = products.first;
        product = BillingProduct(
          id: _productDetails!.id,
          title: _productDetails!.title,
          description: _productDetails!.description,
          price: _productDetails!.price,
        );
        status = BillingStatus.ready;
      } else {
        product = null;
        status = BillingStatus.error;
        error = BillingError(message: 'Підписка недоступна.');
      }
    } catch (e) {
      status = BillingStatus.error;
      error = BillingError(message: 'Не вдалося завантажити підписку', raw: e);
    } finally {
      notifyListeners();
    }
  }

  Future<void> buyPremium() async {
    if (_productDetails == null) {
      error = BillingError(message: 'Немає продукту для покупки');
      notifyListeners();
      return;
    }

    try {
      purchaseState = BillingPurchaseState.purchasing;
      error = null;
      notifyListeners();

      await _service.buy(_productDetails!);
    } catch (e) {
      purchaseState = BillingPurchaseState.error;
      error = BillingError(message: 'Не вдалося ініціювати покупку', raw: e);
      notifyListeners();
    }
  }

  Future<void> restore() async {
    try {
      purchaseState = BillingPurchaseState.restoring;
      error = null;
      notifyListeners();

      await _service.restorePurchases();
    } catch (e) {
      purchaseState = BillingPurchaseState.error;
      error = BillingError(message: 'Не вдалося відновити покупку', raw: e);
      notifyListeners();
    }
  }

  Future<void> _handleUserBecamePremium() async {
    await userNotifier.refreshUserFromMe();
    audioPlayerProvider.userType = getUserType(userNotifier.user);
    purchaseState = BillingPurchaseState.purchased;
    notifyListeners();
  }

  void _handlePurchaseStateChange(BillingPurchaseState state,
      {BillingError? error}) {
    purchaseState = state;
    this.error = error ?? this.error;
    if (state == BillingPurchaseState.error && error != null) {
      debugPrint('Billing: error ${error.message}');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _service.onPurchaseStateChange = null;
    _service.onUserBecamePremium = null;
    super.dispose();
  }
}