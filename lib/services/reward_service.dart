// ПУТЬ: lib/services/reward_service.dart
// Комментарии — русские.
// Единый сервис показа RewardedAd. Без привязки к AudioPlayerProvider —
// просто возвращаем true/false, а начисление минут делаем в месте вызова.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ⚠️ Тестовый unitId от Google. Замените на свой PROD в релизе.
const String kTestRewardedUnitId = 'ca-app-pub-3940256099942544/5224354917';

class RewardService {
  RewardService._();

  /// Показать Rewarded Ad.
  /// Возвращает true, если пользователь реально получил награду (onUserEarnedReward).
  static Future<bool> showRewarded(
      BuildContext context, {
        String? adUnitId,
        VoidCallback? onStartLoading,     // показать лоадер
        VoidCallback? onFinish,           // скрыть лоадер
        void Function(String)? onError,   // подсветить ошибку
      }) async {
    // На web и не-мобайле — не поддерживается.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      onError?.call('Rewarded доступен только на Android/iOS.');
      return false;
    }

    onStartLoading?.call();

    final unitId = adUnitId ?? kTestRewardedUnitId;

    try {
      // ── 1) Загружаем через Completer (API google_mobile_ads v6.x — колбэки) ──
      final rewarded = await _loadRewarded(unitId);

      // ── 2) Показываем ──
      bool rewardedGranted = false;
      await rewarded.show(onUserEarnedReward: (ad, reward) {
        rewardedGranted = true;
      });

      // ── 3) Чистим ресурс и возвращаем результат ──
      rewarded.dispose();
      return rewardedGranted;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    } finally {
      onFinish?.call();
    }
  }

  /// Обёртка над RewardedAd.load(...) для получения Future<RewardedAd>.
  static Future<RewardedAd> _loadRewarded(String adUnitId) {
    final completer = Completer<RewardedAd>();

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) {
            completer.completeError(
              Exception('Не удалось загрузить рекламу: $error'),
            );
          }
        },
      ),
    );

    return completer.future;
  }
}
