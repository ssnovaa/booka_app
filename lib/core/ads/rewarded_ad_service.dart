// ПУТЬ: lib/core/ads/rewarded_ad_service.dart
// Назначение: единый сервис показа Rewarded и ожидания подтверждения (SSV/polling).
// Особенности:
// - load() подготавливает объявление
// - showAndAwaitCredit() показывает и ждёт подтверждения награды с сервера
// - lastError: человекочитаемая причина последней неудачи (для UI)
// - Добавлены колбэки cancelAdTimer / refreshProfile / onGranted для снятия «висячего» таймера и обновления профиля

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:dio/dio.dart';

class RewardedAdService {
  RewardedAdService({
    required Dio dio,
    required int userId,
    String? adUnitId,

    // 🔌 Необязательные колбэки интеграции:
    // - cancelAdTimer: снимет висящий таймер рекламы у провайдера после granted
    // - refreshProfile: обновит профиль/баланс после granted (получим freeSeconds > 0)
    // - onGranted: хук в UI на успешное начисление
    // - onClosed, onError, onImpression: дополнительные UI-хуки по желанию
    FutureOr<void> Function(String reason)? cancelAdTimer,
    FutureOr<void> Function()? refreshProfile,
    VoidCallback? onGranted,
    VoidCallback? onClosed,
    VoidCallback? onImpression,
    void Function(String message)? onError,
  })  : _dio = dio,
        _userId = userId,
        cancelAdTimer = cancelAdTimer,
        refreshProfile = refreshProfile,
        onGranted = onGranted,
        onClosed = onClosed,
        onImpression = onImpression,
        onError = onError,
  // ✅ твой PROD rewarded unit
        adUnitId = adUnitId ?? 'ca-app-pub-9743644418783616/4630987177';

  final Dio _dio;
  final int _userId;

  /// PROD ad unit (можно переопределить через конструктор)
  final String adUnitId;

  /// Колбэки интеграции (все опциональны)
  final FutureOr<void> Function(String reason)? cancelAdTimer;
  final FutureOr<void> Function()? refreshProfile;
  final VoidCallback? onGranted;
  final VoidCallback? onClosed;
  final VoidCallback? onImpression;
  final void Function(String message)? onError;

  RewardedAd? _ad;
  bool _isLoaded = false;
  bool _isShowing = false;

  String? _lastError;
  String? get lastError => _lastError;

  bool get isLoaded => _isLoaded && _ad != null;
  bool get isShowing => _isShowing;

  // Таймауты/параметры ожиданий
  static const Duration _showEarnTimeout = Duration(minutes: 2);
  static const int _pollAttemptsDefault = 8;
  static const Duration _pollDelayDefault = Duration(seconds: 2);

  void _setError(String message) {
    _lastError = message;
    debugPrint('[REWARD][ERR] $message');
    try {
      onError?.call(message);
    } catch (_) {}
  }

  void _dispose() {
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
    _isLoaded = false;
    _isShowing = false;
  }

  /// Полная очистка + опционально снять таймер (например, при ручном сбросе сценария).
  Future<void> forceDispose({String reason = 'force_dispose'}) async {
    await _safeCancelTimer(reason: reason);
    _dispose();
  }

  /// Прелоад объявления. Возвращает true, если готово к показу.
  Future<bool> load() async {
    if (_isLoaded && _ad != null) return true;

    final completer = Completer<bool>();
    _lastError = null;
    debugPrint('[REWARD] load() → start (unit=$adUnitId)');

    await RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          debugPrint('[REWARD] onAdLoaded (id=${ad.responseInfo?.responseId})');
          _ad = ad;
          _isLoaded = true;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              debugPrint('[REWARD] onAdShowedFullScreenContent');
              _isShowing = true;
            },
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('[REWARD] onAdDismissedFullScreenContent');
              _isShowing = false;
              try {
                onClosed?.call();
              } catch (_) {}
              ad.dispose();
              _ad = null;
              _isLoaded = false;
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              _setError('Не удалось показать рекламу: ${err.message}');
              _isShowing = false;
              ad.dispose();
              _ad = null;
              _isLoaded = false;
            },
            onAdImpression: (ad) {
              debugPrint('[REWARD] onAdImpression');
              try {
                onImpression?.call();
              } catch (_) {}
            },
          );

          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (LoadAdError error) {
          _setError('Не удалось загрузить рекламу: ${error.message}');
          _dispose();
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    final ok = await completer.future;
    debugPrint('[REWARD] load() → $ok');
    return ok;
  }

  /// Показать рекламу и дождаться подтверждения награды сервером.
  /// Возвращает true, если сервер подтвердил начисление.
  Future<bool> showAndAwaitCredit({
    int maxAttempts = _pollAttemptsDefault,
    Duration delay = _pollDelayDefault,
  }) async {
    _lastError = null;

    // 0) Грузим объявление при необходимости
    if (!isLoaded) {
      final ok = await load();
      if (!ok || _ad == null) {
        _setError(_lastError ?? 'Реклама недоступна (load=false)');
        return false;
      }
    }

    // 1) Запрашиваем одноразовый nonce у сервера
    final nonce = await _requestNonce();
    if (nonce == null || nonce.isEmpty) {
      _lastError ??= 'Сервер не выдал одноразовый токен (nonce).';
      _dispose();
      return false;
    }

    // 2) Устанавливаем SSV-параметры
    try {
      final ssv = ServerSideVerificationOptions(
        userId: _userId.toString(),
        customData: '{"nonce":"$nonce"}',
      );
      await _ad!.setServerSideOptions(ssv);
      debugPrint('[REWARD] SSV set: userId=$_userId, nonce=$nonce');
    } catch (e) {
      _setError('Не удалось применить SSV-настройки: $e');
      _dispose();
      return false;
    }

    // 3) Показ → ждём onUserEarnedReward
    final earned = Completer<bool>();
    bool earnedFlag = false;

    debugPrint('[REWARD] show()');
    try {
      await _ad!.setImmersiveMode(true);
      await _ad!.show(onUserEarnedReward: (ad, reward) async {
        earnedFlag = true;
        debugPrint('[REWARD] onUserEarnedReward: ${reward.amount} ${reward.type}');
        if (!earned.isCompleted) earned.complete(true);
      });
    } catch (e) {
      _setError('Ошибка показа объявления: $e');
      _dispose();
      return false;
    }

    final bool gotEarned = await earned.future
        .timeout(_showEarnTimeout, onTimeout: () => false);

    if (!gotEarned || !earnedFlag) {
      _setError('Награда не получена (пользователь закрыл объявление или истёк таймаут).');
      _dispose();
      return false;
    }

    // 4) Ждём подтверждение сервера (SSV придёт на /api/admob/ssv; здесь — polling по nonce)
    final bool credited = await _pollRewardStatus(
      nonce: nonce,
      adUnitId: adUnitId,
      maxAttempts: maxAttempts,
      delay: delay,
    );

    if (!credited) {
      _setError('Сервер не подтвердил награду (status != granted).');
      _dispose();
      return false;
    }

    // ✅ Награда подтверждена:
    //    - снимаем висящий таймер рекламы
    //    - обновляем профиль (получим freeSeconds > 0 → провайдер сам выключит ad-mode)
    try {
      await _safeCancelTimer(reason: 'reward_granted');
      await _safeRefreshProfile();
      onGranted?.call();
    } catch (_) {}

    debugPrint('[REWARD] credited=true');
    _dispose();
    return true;
  }

  /// POST /rewards/prepare → { nonce: "..." }
  Future<String?> _requestNonce() async {
    try {
      debugPrint('[REWARD] POST /rewards/prepare');
      final r = await _dio.post(
        '/rewards/prepare',
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (r.statusCode == 200 && r.data is Map) {
        final data = r.data as Map;
        final nonce = (data['nonce'] ?? '').toString();
        debugPrint('[REWARD] nonce=$nonce');
        return nonce;
      }
      _setError('Неизвестный ответ /rewards/prepare: код ${r.statusCode}');
      return null;
    } catch (e) {
      _setError('Ошибка /rewards/prepare: $e');
      return null;
    }
  }

  /// Поллинг статуса награды: GET /rewards/status?nonce=...&ad_unit_id=...
  /// Считаем успехом:
  /// - HTTP 200 с JSON, где status == granted/ok (без учёта регистра), или
  /// - HTTP 200 без тела (некоторые бэки отвечают просто 200/ok).
  Future<bool> _pollRewardStatus({
    required String nonce,
    required String adUnitId,
    int maxAttempts = _pollAttemptsDefault,
    Duration delay = _pollDelayDefault,
  }) async {
    for (int i = 1; i <= maxAttempts; i++) {
      try {
        debugPrint('[REWARD] status(attempt=$i) → GET /rewards/status?nonce=...&ad_unit_id=$adUnitId');
        final r = await _dio.get(
          '/rewards/status',
          queryParameters: <String, dynamic>{
            'nonce': nonce,
            'ad_unit_id': adUnitId,
          },
          options: Options(
            responseType: ResponseType.json,
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

        debugPrint('✅ ${r.statusCode} ${r.realUri}');
        if (r.statusCode == 200) {
          if (r.data is Map) {
            final data = r.data as Map;
            final status = (data['status'] ?? '').toString().toLowerCase();
            debugPrint('[REWARD] status body=$data');
            if (status.isEmpty || status == 'granted' || status == 'ok') {
              return true;
            }
          } else {
            // 200 без тела — тоже считаем успехом
            return true;
          }
        } else {
          _setError('Статус награды: код ${r.statusCode}');
        }
      } catch (e) {
        // не падаем — пробуем ещё
        _setError('Ошибка запроса статуса награды: $e');
      }

      await Future.delayed(delay);
    }
    return false;
  }

  // ---------- ВСПОМОГАТЕЛЬНЫЕ БЕЗОПАСНЫЕ ВЫЗОВЫ ИНТЕГРАЦИИ ----------

  Future<void> _safeCancelTimer({required String reason}) async {
    try {
      if (cancelAdTimer != null) {
        await cancelAdTimer!(reason);
        debugPrint('[REWARD] cancelAdTimer(reason=$reason) → OK');
      }
    } catch (e) {
      debugPrint('[REWARD] cancelAdTimer failed: $e');
    }
  }

  Future<void> _safeRefreshProfile() async {
    try {
      if (refreshProfile != null) {
        await refreshProfile!();
        debugPrint('[REWARD] refreshProfile() → OK');
      }
    } catch (e) {
      debugPrint('[REWARD] refreshProfile failed: $e');
    }
  }
}
