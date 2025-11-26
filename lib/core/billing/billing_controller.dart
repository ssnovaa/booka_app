// ПУТЬ: lib/core/billing/billing_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // Добавлен import для PlatformException
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:booka_app/core/billing/billing_models.dart';
import 'package:booka_app/core/billing/billing_service.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart';
import 'package:booka_app/providers/audio_player_provider.dart';

/// Контроллер подписки:
// ... (комментарии)
class BillingController extends ChangeNotifier {
  /// Единственный SKU подписки в Google Play.
  static const String kSubscriptionProductId = 'booka_premium_month';

  final BillingService _service;
  final UserNotifier _userNotifier;
  final AudioPlayerProvider _audio;

  BillingStatus _status = BillingStatus.idle;
  BillingPurchaseState _purchaseState = BillingPurchaseState.none;
  BillingError? _lastError;

  /// Упрощённая модель продуктов для UI.
  List<BillingProduct> _products = const [];

  /// Сырые объекты ProductDetails, по id.
  final Map<String, ProductDetails> _rawProducts = {};

  // ---- геттеры для UI ----

  BillingStatus get status => _status;
  BillingPurchaseState get purchaseState => _purchaseState;
  BillingError? get lastError => _lastError;

  List<BillingProduct> get products => List.unmodifiable(_products);

  /// Текущая подписка (если найдена в сторе).
  BillingProduct? get subscriptionProduct =>
      _products.where((p) => p.id == kSubscriptionProductId).firstOrNull ??
          (_products.isNotEmpty ? _products.first : null);

  /// Сырой ProductDetails для покупки.
  ProductDetails? get _subscriptionProductDetails {
    final id = subscriptionProduct?.id ?? kSubscriptionProductId;
    return _rawProducts[id];
  }

  bool get isLoading =>
      _status == BillingStatus.loadingProducts ||
          _purchaseState == BillingPurchaseState.purchasing ||
          _purchaseState == BillingPurchaseState.restoring;

  bool get hasError =>
      _status == BillingStatus.error ||
          _purchaseState == BillingPurchaseState.error;

  bool get isPaidUser => getUserType(_userNotifier.user) == UserType.paid;

  BillingController({
    required BillingService service,
    required UserNotifier userNotifier,
    required AudioPlayerProvider audioPlayerProvider,
  })  : _service = service,
        _userNotifier = userNotifier,
        _audio = audioPlayerProvider {
    // Все результаты покупок приходят через этот колбэк.
    _service.onPurchaseStateChange = _handlePurchaseStateChange;
  }

  // ---------------------------------------------------------------------------
  // ИНИЦИАЛИЗАЦИЯ
  // ---------------------------------------------------------------------------

  /// Полная инициализация биллинга:
  /// - подключаемся к Google Play;
  /// - подтягиваем продукт подписки.
  Future<void> init() async {
    if (_status == BillingStatus.loadingProducts) return;

    _status = BillingStatus.loadingProducts;
    _lastError = null;
    notifyListeners();

    try {
      await _service.init();
      await _reloadProductsInternal();
      _status = BillingStatus.ready;
    } catch (e, st) {
      _status = BillingStatus.error;
      _lastError = BillingError(
        message: 'Помилка ініціалізації білінгу: $e',
        raw: st,
      );
      debugPrint('BillingController: Init error: $e\n$st'); // ⬅️ NEW DEBUG
    }

    notifyListeners();
  }

  Future<void> reloadProducts() async {
    await _ensureInitialized();
    await _reloadProductsInternal();
    notifyListeners();
  }

  Future<void> _reloadProductsInternal() async {
    try {
      // Сейчас у нас один SKU, но API поддерживает множество.
      final set = <String>{kSubscriptionProductId};
      final rawList = await _service.queryProducts(set);

      _rawProducts
        ..clear()
        ..addEntries(rawList.map((p) => MapEntry(p.id, p)));

      _products = rawList
          .map(
            (p) => BillingProduct(
          id: p.id,
          title: p.title,
          description: p.description,
          price: p.price, // форматированная строка, напр. "₴99.00"
          currency: p.currencyCode,
          raw: p,
        ),
      )
          .toList();

      if (_products.isEmpty) {
        _lastError = const BillingError(
          message: 'Підписка у Play Store не знайдена.',
        );
      }
    } catch (e, st) {
      _lastError = BillingError(
        message: 'Не вдалося завантажити продукти з магазину: $e',
        raw: st,
      );
      debugPrint('BillingController: Product query error: $e\n$st'); // ⬅️ NEW DEBUG
    }
  }

  Future<void> _ensureInitialized() async {
    if (_status == BillingStatus.idle) {
      await init();
    }
  }

  // ---------------------------------------------------------------------------
  // ПОКУПКА
  // ---------------------------------------------------------------------------

  /// Запуск покупки подписки.
  Future<void> buySubscription({bool isRetry = false}) async { // Добавляем флаг isRetry
    await _ensureInitialized();

    if (_subscriptionProductDetails == null) {
      await reloadProducts();
    }

    final product = _subscriptionProductDetails;
    if (product == null) {
      _purchaseState = BillingPurchaseState.error;
      _lastError = const BillingError(
        message: 'Продукт підписки недоступний. Спробуйте пізніше.',
      );
      notifyListeners();
      return;
    }

    // Если это первая попытка, переводим в Purchasing
    if (!isRetry) {
      _purchaseState = BillingPurchaseState.purchasing;
      _lastError = null;
      notifyListeners();
    }

    try {
      await _service.buy(product);
      debugPrint('BillingController: Buy initiated successfully.'); // ⬅️ NEW DEBUG
      // Далее события придут через _handlePurchaseStateChange.
    } on PlatformException catch (e) {

      // 🚨 ЛОВИМ ОШИБКУ DISCONNECT/UNSET И ПОВТОРЯЕМ
      if (!isRetry && e.code == 'UNAVAILABLE' && (e.message?.contains('BillingClient is unset') == true || e.message?.contains('is not ready') == true)) {
        debugPrint('BillingController: Caught UNSET error. Re-initializing and retrying purchase (first retry).');

        // 1. Сбрасываем статус, чтобы init() мог переподключиться
        _status = BillingStatus.idle;
        _purchaseState = BillingPurchaseState.none;
        // НЕ вызываем notifyListeners(), чтобы не перерисовывать UI перед retry

        await init(); // Повторная инициализация

        if (_status == BillingStatus.ready) {
          debugPrint('BillingController: Re-initialization successful. Retrying purchase...');
          // Повторяем вызов с флагом isRetry=true
          return buySubscription(isRetry: true);
        }
      }

      // 3. Финальная обработка ошибки (после failed retry или если это другая ошибка)
      _purchaseState = BillingPurchaseState.error;
      _lastError = BillingError(
        message: 'Не вдалося запустити покупку: ${e.message}',
        raw: e,
      );
      debugPrint('BillingController: Final PlatformException error: ${e.code} - ${e.message}');
      notifyListeners();

    } catch (e, st) {
      // 4. Ловим общие ошибки
      _purchaseState = BillingPurchaseState.error;
      _lastError = BillingError(
        message: 'Не вдалося запустити покупку: $e',
        raw: st,
      );
      debugPrint('BillingController: Final generic error during purchase initiation: $e\n$st');
      notifyListeners();
    }
  }

  /// Восстановление подписки с Google Play.
  Future<void> restore() async {
    await _ensureInitialized();

    _purchaseState = BillingPurchaseState.restoring;
    _lastError = null;
    notifyListeners();

    try {
      await _service.restorePurchases();
      // Результат восстановления тоже придёт через _handlePurchaseStateChange.
    } catch (e, st) {
      debugPrint('BillingController: Error caught during restore initiation: $e\n$st'); // ⬅️ NEW DEBUG
      _purchaseState = BillingPurchaseState.error;
      _lastError = BillingError(
        message: 'Не вдалося відновити покупки: $e',
        raw: st,
      );
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // СИНХРОНИЗАЦИЯ С БЕКЕНДОМ / ПЛЕЕРОМ
  // ---------------------------------------------------------------------------

  /// Подтягиваем свежие данные пользователя и синхронизируем плеер.
  Future<void> refreshUser() async {
    try {
      await _userNotifier.refreshUserFromMe();

      // Обновляем тип пользователя в плеере (режим рекламы/кредиты).
      _audio.userType = getUserType(_userNotifier.user);
      await _audio.ensureCreditsTickerBound();
    } catch (e) {
      if (kDebugMode) {
        // В релизе тихо игнорируем.
        // ignore: avoid_print
        print('[BillingController] refreshUser() failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // КОЛБЭК ОТ BillingService
  // ---------------------------------------------------------------------------

  void _handlePurchaseStateChange(
      BillingPurchaseState state, {
        BillingError? error,
      }) async {
    debugPrint('BillingController: Received state update: $state, Error: ${error?.message ?? 'none'}'); // ⬅️ NEW DEBUG
    _purchaseState = state;
    _lastError = error;
    notifyListeners();

    switch (state) {
      case BillingPurchaseState.purchased:
      // На этом этапе:
      //  - Google Play завершил транзакцию;
      //  - BillingService уже дернул бекенд verify + acknowledge;
      //  - нам осталось обновить пользователя и вернуть UI в норму.
        await refreshUser();
        _purchaseState = BillingPurchaseState.none;
        notifyListeners();
        break;

      case BillingPurchaseState.purchasing:
      case BillingPurchaseState.restoring:
      // Просто ждём следующего состояния.
        break;

      case BillingPurchaseState.error:
      // Ошибка уже лежит в _lastError, UI может её показать.
        break;

      case BillingPurchaseState.none:
      // Спокойное состояние — ничего делать не нужно.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // ЖИЗНЕННЫЙ ЦИКЛ
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    // Отцепляемся от сервиса, чтобы не держать висячие ссылки.
    _service.onPurchaseStateChange = null;
    super.dispose();
  }
}

// Небольшое расширение, чтобы аккуратно брать первый элемент или null.
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}