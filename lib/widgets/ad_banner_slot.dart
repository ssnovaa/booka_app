// lib/widgets/ad_banner_slot.dart
// ПОЛНЫЙ ФАЙЛ БЕЗ СОКРАЩЕНИЙ

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart' show UserType; // enum UserType
import 'package:booka_app/widgets/ad_banner.dart';

/// Обёртка, которая решает — показывать баннер или нет.
/// Показываем только для guest и free. Для paid — скрыто.
/// ВАЖНО: мы не dispose/создаём баннер по кругу — виджет AdBanner сам
/// хранит BannerAd и безопасен к пересборкам, а тут мы просто
/// скрываем слот, когда реклама не нужна.
class AdBannerSlot extends StatelessWidget {
  /// Тестовый Unit ID (AdMob). Перед выпуском замените на реальный.
  /// Android тест баннера: 'ca-app-pub-3940256099942544/6300978111'
  final String adUnitId;

  /// Дополнительный внешний отступ для слота, если нужно.
  final EdgeInsets padding;

  const AdBannerSlot({
    super.key,
    this.adUnitId = 'ca-app-pub-3940256099942544/6300978111',
    this.padding = EdgeInsets.zero,
  });

  bool _adsEnabled(UserType t) {
    switch (t) {
      case UserType.guest:
      case UserType.free:
        return true;
      case UserType.paid:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ререндерим только при смене userType (Selector оптимизирует rebuild).
    final userType = context.select<AudioPlayerProvider, UserType>((p) => p.userType);
    final enabled = _adsEnabled(userType);

    if (!enabled) {
      // Ничего не рендерим и не пересоздаём платформенный вид (AdView).
      return const SizedBox.shrink();
    }

    // Слот баннера без доп. отступа сверху, чтобы был вплотную к контенту.
    return SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: Center(
          // AdBanner сам хранит BannerAd и не пересоздаёт его на каждый build.
          child: AdBanner(
            adUnitId: adUnitId,
            // При необходимости можно передать size/padding/visible:
            // size: AdSize.banner,
            // padding: EdgeInsets.symmetric(vertical: 8),
            // visible: true,
          ),
        ),
      ),
    );
  }
}
