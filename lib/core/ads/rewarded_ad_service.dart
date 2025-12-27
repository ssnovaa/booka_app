// ПУТЬ: lib/core/ads/rewarded_ad_service.dart
// Назначение: единый сервис показа Rewarded и ожидания подтверждения (SSV/polling).
// Особенности:
// - load() подготавливает объявление
// - showAndAwaitCredit() показывает и ждёт подтверждения награды с сервера
// - lastError: человекочитаемая причина последней неудачи (для UI)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:dio/dio.dart';

class RewardedAdService {
  RewardedAdService({
    required Dio dio,
    required int userId,
    String? adUnitId,
  })  : _dio = dio,
        _userId = userId,
  // ✅ твой PROD rewarded unit
        adUnitId = adUnitId ?? 'ca-app-pub-9743644418783616/4630987177';

  final Dio _dio;
  final int _userId;

  /// PROD ad unit (можно переопределить через конструктор)
  final String adUnitId;

  RewardedAd? _ad;
  bool _isLoaded = false;
  bool _isShowing = false;

  String? _lastError;
  String? get lastError => _lastError;

  void _setError(String message) {
    _lastError = message;
    debugPrint('[REWARD][ERR] $message');
  }

  void _dispose() {
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
    _isLoaded = false;
    _isShowing = false;
  }

  /// Прерывает текущую загрузку/показ и очищает ресурс.
  void cancel({String reason = 'Показ винагородної реклами скасовано.'}) {
    _setError(reason);
    _dispose();
  }

  /// Прелоад объявления. Возвращает true, если готово к показу.
  Future<bool> load() async {
    if (_isLoaded && _ad != null) return true;

    final completer = Completer<bool>();
    _lastError = null;
    debugPrint('[REWARD] load() → start');

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
              ad.dispose();
              _ad = null;
              _isLoaded = false;
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              _setError('Не вдалося показати рекламу: ${err.message}');
              _isShowing = false;
              ad.dispose();
              _ad = null;
              _isLoaded = false;
            },
            onAdImpression: (ad) => debugPrint('[REWARD] onAdImpression'),
          );

          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (LoadAdError error) {
          _setError('Не вдалося завантажити рекламу: ${error.message}');
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
  Future<bool> showAndAwaitCredit() async {
    _lastError = null;

    if (!_isLoaded || _ad == null) {
      final ok = await load();
      if (!ok || _ad == null) {
        _setError(_lastError ?? 'Реклама недоступна (load=false)');
        return false;
      }
    }

    if (_ad == null) {
      _setError('Показ скасовано: оголошення недоступне.');
      return false;
    }

    // 1) Запрашиваем одноразовый nonce у сервера
    final nonce = await _requestNonce();
    if (nonce == null || nonce.isEmpty) {
      _lastError ??= 'Сервер не видав одноразовий токен (nonce).';
      _dispose();
      return false;
    }

    if (_ad == null) {
      _setError('Показ скасовано до відображення оголошення.');
      return false;
    }

    // 2) Устанавливаем SSV-параметры (ВАЖНО: в v6.0.0 метод называется setServerSideOptions)
    try {
      final ssv = ServerSideVerificationOptions(
        userId: _userId.toString(),
        customData: '{"nonce":"$nonce"}',
      );
      await _ad!.setServerSideOptions(ssv);
      debugPrint('[REWARD] SSV set: userId=$_userId, nonce=$nonce');
    } catch (e) {
      _setError('Не вдалося застосувати SSV-налаштування: $e');
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
      _setError('Помилка показу оголошення: $e');
      _dispose();
      return false;
    }

    final bool gotEarned = await earned.future
        .timeout(const Duration(minutes: 2), onTimeout: () => false);

    if (!gotEarned || !earnedFlag) {
      _setError('Нагороду не отримано (користувач закрив оголошення або минув час очікування).');
      _dispose();
      return false;
    }

    // 4) Ждём подтверждение сервера (SSV придёт на /api/admob/ssv; здесь — polling по nonce)
    final bool credited = await _pollRewardStatus(
      nonce: nonce,
      adUnitId: adUnitId,
      maxAttempts: 8,
      delay: const Duration(seconds: 2),
    );

    if (!credited) {
      _setError('Сервер не підтвердив нагороду (status != granted).');
    }

    debugPrint('[REWARD] credited=$credited');
    _dispose();
    return credited;
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
      _setError('Невідома відповідь /rewards/prepare: код ${r.statusCode}');
      return null;
    } catch (e) {
      _setError('Помилка /rewards/prepare: $e');
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
    int maxAttempts = 8,
    Duration delay = const Duration(seconds: 2),
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
          _setError('Статус нагороди: код ${r.statusCode}');
        }
      } catch (e) {
        // не падаем — пробуем ещё
        _setError('Помилка запиту статусу нагороди: $e');
      }

      await Future.delayed(delay);
    }
    return false;
  }
}