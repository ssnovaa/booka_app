// ПУТЬ: lib/widgets/ad_banner.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Универсальный баннер AdMob, безопасный к пересборкам.
/// - BannerAd создаётся один раз в initState и хранится в State
/// - Не пересоздаётся на каждый build/setState
/// - Пересоздаётся только при изменении adUnitId или размеров
/// - При скрытии не dispose, а просто не рендерим (чтобы не дёргать PlatformView)
class AdBanner extends StatefulWidget {
  final String adUnitId;
  final AdSize size;
  final EdgeInsets padding;
  final bool visible;

  const AdBanner({
    super.key,
    required this.adUnitId,
    this.size = AdSize.banner,
    this.padding = EdgeInsets.zero,
    this.visible = true,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner>
    with AutomaticKeepAliveClientMixin<AdBanner> {
  BannerAd? _bannerAd;
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _createAndLoad();
  }

  @override
  void didUpdateWidget(covariant AdBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пересоздаём баннер только при реальном изменении параметров
    final sizeChanged = oldWidget.size.width != widget.size.width ||
        oldWidget.size.height != widget.size.height;

    if (oldWidget.adUnitId != widget.adUnitId || sizeChanged) {
      _disposeBanner();
      _createAndLoad();
    }
  }

  void _createAndLoad() {
    // На вебе/десктопе баннер не грузим, чтобы не ловить ошибки PlatformView
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      setState(() {
        _loaded = false;
        _bannerAd = null;
      });
      return;
    }

    final banner = BannerAd(
      size: widget.size,
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _loaded = true;
            // Нормализуем тип.
            _bannerAd = ad as BannerAd;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint('BannerAd failed to load: $error');
          }
          if (mounted) {
            setState(() {
              _loaded = false;
              _bannerAd = null;
            });
          }
        },
      ),
    );

    // Сохраняем ссылку сразу, чтобы гарантированно корректно dispose в любом сценарии
    _bannerAd = banner;
    banner.load();
  }

  void _disposeBanner() {
    try {
      _bannerAd?.dispose();
    } catch (_) {
      // ignore
    } finally {
      _bannerAd = null;
      _loaded = false;
    }
  }

  @override
  void dispose() {
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Если баннер скрыт — не удаляем/создаём по кругу, просто не рисуем.
    if (!widget.visible) {
      return const SizedBox.shrink();
    }

    // Держим место под баннер до загрузки, чтобы не прыгала вёрстка.
    final h = widget.size.height.toDouble();
    final w = widget.size.width.toDouble();

    if (!_loaded || _bannerAd == null) {
      return Padding(
        padding: widget.padding,
        child: SizedBox(width: w, height: h),
      );
    }

    // ВАЖНО: один AdWidget на один BannerAd, обёрнутый в RepaintBoundary,
    // чтобы ограничить лишние перерисовки вокруг PlatformView.
    return Padding(
      padding: widget.padding,
      child: SizedBox(
        width: w,
        height: h,
        child: RepaintBoundary(
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}
