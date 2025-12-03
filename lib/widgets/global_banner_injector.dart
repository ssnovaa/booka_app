// ПУТЬ: lib/widgets/global_banner_injector.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart' show UserType;

/// Нижний слой: баннер (AdMob) или CTA («Отримати ще 15 хвилин»).
/// guest  -> всегда баннер
/// free   -> СТА сразу (как только узнаем статус) и далее по таймеру; когда СТА скрыт — баннер
/// paid   -> ничего
class GlobalBannerInjector extends StatefulWidget {
  final Widget child;

  final String adUnitId;
  final AdSize? adSize;

  // Настройки СТА (работают только для free)
  final Duration ctaInterval;   // периодичность показа
  final Duration ctaDuration;   // длительность одного окна
  final Duration firstCtaDelay; // начальная задержка первого показа

  /// Опциональный обработчик CTA. Если задан — вызывается при нажатии.
  /// Если НЕ задан — выполнится переход по [ctaRouteName] через [navigatorKey].
  final Future<void> Function(BuildContext)? ctaAction;

  /// Именованный маршрут экрана «как у Reward test». Используется, если [ctaAction] не задан.
  final String ctaRouteName;

  /// Ключ навигатора приложения. Нужен, потому что инжектор живёт в MaterialApp.builder,
  /// выше дерева Navigator — поэтому Navigator.of(context) недоступен.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Кастомный билдёр внешнего вида CTA (если нужен). Вы получите onPressed.
  final Widget Function(BuildContext, VoidCallback)? ctaBuilder;

  const GlobalBannerInjector({
    super.key,
    required this.child,
    this.adUnitId = 'ca-app-pub-3940256099942544/6300978111',
    this.adSize,
    this.ctaInterval = const Duration(minutes: 1),
    this.ctaDuration = const Duration(seconds: 15),
    this.firstCtaDelay = Duration.zero,
    this.ctaAction,
    this.ctaRouteName = '/rewarded',
    this.navigatorKey,
    this.ctaBuilder,
  });

  @override
  State<GlobalBannerInjector> createState() => _GlobalBannerInjectorState();
}

class _GlobalBannerInjectorState extends State<GlobalBannerInjector>
    with WidgetsBindingObserver {
  // ---- Ads ----
  BannerAd? _ad;
  AdWidget? _adView; // один экземпляр
  bool _isLoaded = false;
  bool _loading = false;
  double _bannerHeight = 0;

  // ---- CTA ----
  bool _ctaVisible = false;
  Timer? _ctaTick;
  Timer? _ctaAutoHide;
  final double _ctaHeight = AdSize.banner.height.toDouble();

  // ---- Metrics debounce ----
  Timer? _metricsDebounce;

  // ---- Guard (от дабл-тапа) ----
  bool _ctaInProgress = false;

  // ---- Подписка на провайдер ----
  UserType? _lastUserType;
  VoidCallback? _providerListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Подписка на изменения провайдера
    Future.microtask(() {
      if (!mounted) return;
      final ap = context.read<AudioPlayerProvider>();
      _lastUserType = ap.userType;
      _providerListener = () {
        final t = ap.userType;
        if (t != _lastUserType) {
          _lastUserType = t;
          _onUserTypeChanged(t);
        }
      };
      ap.addListener(_providerListener!);
      _onUserTypeChanged(ap.userType, initial: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = context.read<AudioPlayerProvider>().userType;
    if (_lastUserType != t) {
      _lastUserType = t;
      _onUserTypeChanged(t, initial: true);
    }
  }

  void _onUserTypeChanged(UserType t, {bool initial = false}) {
    _maybeInitAds();
    _configureCtaCycle();

    if (t == UserType.free) {
      _showFirstCtaNow();
    } else {
      _hideCta();
      _stopCtaCycle();
    }
  }

  Future<void> _showFirstCtaNow() async {
    if (!_ctaAllowed) return;
    if (widget.firstCtaDelay > Duration.zero) {
      await Future.delayed(widget.firstCtaDelay);
      if (!mounted || !_ctaAllowed) return;
    }
    _showCtaWindow();
  }

  @override
  void didUpdateWidget(covariant GlobalBannerInjector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.adUnitId != widget.adUnitId || oldWidget.adSize != widget.adSize) {
      _disposeAd();
      _maybeInitAds();
    }

    if (oldWidget.ctaInterval != widget.ctaInterval ||
        oldWidget.ctaDuration != widget.ctaDuration ||
        oldWidget.firstCtaDelay != widget.firstCtaDelay ||
        oldWidget.ctaBuilder != widget.ctaBuilder ||
        oldWidget.ctaAction != widget.ctaAction ||
        oldWidget.ctaRouteName != widget.ctaRouteName ||
        oldWidget.navigatorKey != widget.navigatorKey) {
      _configureCtaCycle();
      _showFirstCtaNow();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (widget.adSize == null && _ad != null) {
      _metricsDebounce?.cancel();
      _metricsDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        _disposeAd();
        _maybeInitAds();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metricsDebounce?.cancel();
    _stopCtaCycle();
    _disposeAd();

    final ap = context.read<AudioPlayerProvider>();
    if (_providerListener != null) {
      ap.removeListener(_providerListener!);
      _providerListener = null;
    }
    super.dispose();
  }

  // =================== ADS ===================

  bool _adsEnabled(UserType t) {
    switch (t) {
      case UserType.guest:
      case UserType.free:
        return true;
      case UserType.paid:
        return false;
    }
  }

  void _disposeAd() {
    _isLoaded = false;
    _adView = null;
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
  }

  Future<void> _maybeInitAds() async {
    if (!mounted || _loading) return;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    final t = _lastUserType ?? context.read<AudioPlayerProvider>().userType;
    if (!_adsEnabled(t)) {
      if (_ad != null) {
        setState(() {
          _disposeAd();
          _bannerHeight = 0;
        });
      }
      return;
    }

    _loading = true;
    try {
      AdSize sizeToUse;
      if (widget.adSize != null) {
        sizeToUse = widget.adSize!;
      } else {
        final widthPx = MediaQuery.of(context).size.width;
        final width = widthPx.isFinite ? widthPx.truncate() : AdSize.banner.width;
        final adaptive =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
        sizeToUse = adaptive ?? AdSize.banner;
      }
      _bannerHeight = sizeToUse.height.toDouble();

      final ad = BannerAd(
        adUnitId: widget.adUnitId,
        size: sizeToUse,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            final loadedAd = ad as BannerAd;
            setState(() {
              _ad = loadedAd;
              _isLoaded = true;
              _adView = AdWidget(ad: loadedAd);
              _bannerHeight = loadedAd.size.height.toDouble();
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (!mounted) return;
            if (kDebugMode) {
              debugPrint('Global banner failed to load: $error');
            }
            setState(() {
              _isLoaded = false;
              _adView = null;
              _ad = null;
              _bannerHeight = 0;
            });
          },
        ),
      );

      await ad.load();
      _ad = ad;
    } finally {
      _loading = false;
    }
  }

  // =================== CTA ===================

  bool get _ctaAllowed {
    final t = _lastUserType ?? context.read<AudioPlayerProvider>().userType;
    return t == UserType.free; // guest — только баннер; paid — ничего
  }

  void _configureCtaCycle() {
    if (!_ctaAllowed) {
      _hideCta();
      _stopCtaCycle();
      return;
    }
    _startCtaCycleIfNeeded();
  }

  void _startCtaCycleIfNeeded() {
    _ctaTick ??= Timer.periodic(widget.ctaInterval, (_) {
      if (!mounted || !_ctaAllowed) return;
      _showCtaWindow();
    });
  }

  void _stopCtaCycle() {
    _ctaTick?.cancel();
    _ctaTick = null;
    _ctaAutoHide?.cancel();
    _ctaAutoHide = null;
    _ctaVisible = false;
  }

  void _showCtaWindow() {
    if (!_ctaAllowed) return;
    setState(() => _ctaVisible = true);

    _ctaAutoHide?.cancel();
    _ctaAutoHide = Timer(widget.ctaDuration, () {
      if (!mounted) return;
      _hideCta();
    });

    if (kDebugMode) {
      debugPrint('[CTA] show (${widget.ctaDuration.inSeconds}s)');
    }
  }

  void _hideCta() {
    if (_ctaVisible) {
      setState(() => _ctaVisible = false);
      if (kDebugMode) debugPrint('[CTA] hide');
    }
  }

  // =================== VISIBILITY ===================

  bool get _shouldShowBanner {
    final t = _lastUserType ?? context.read<AudioPlayerProvider>().userType;
    if (!_adsEnabled(t)) return false;
    if (t == UserType.guest) return _isLoaded && _adView != null;
    // free — баннер только когда СТА скрыт
    return !_ctaVisible && _isLoaded && _adView != null;
  }

  bool get _shouldShowCta => _ctaVisible && _ctaAllowed;

  @override
  Widget build(BuildContext context) {
    final double bottomInset =
    _shouldShowCta ? _ctaHeight : (_shouldShowBanner ? _bannerHeight : 0.0);

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: widget.child,
        ),

        if (_shouldShowCta)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: _buildCtaBar(context),
            ),
          ),

        if (_shouldShowBanner)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: Center(
                child: SizedBox(
                  height: _bannerHeight,
                  width: _ad?.size.width.toDouble(),
                  child: RepaintBoundary(child: _adView),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// УПРОЩЁННЫЙ СТА: одна горизонтальная кнопка «Отримати ще 15 хвилин».
  /// Никакого дефолтного Rewarded. По нажатию:
  /// 1) если задан widget.ctaAction — вызываем его;
  /// 2) иначе используем navigatorKey для pushNamed(ctaRouteName).
  Widget _buildCtaBar(BuildContext context) {
    final onPressed = () async {
      if (_ctaInProgress) return;
      _ctaInProgress = true;

      if (kDebugMode) debugPrint('[CTA] pressed');

      try {
        if (widget.ctaAction != null) {
          await widget.ctaAction!(context);
        } else {
          final nav = widget.navigatorKey?.currentState;
          if (nav != null) {
            await nav.pushNamed(widget.ctaRouteName);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Navigator недоступен: передайте navigatorKey в GlobalBannerInjector',
                  ),
                ),
              );
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось открыть экран: $e')),
          );
        }
      } finally {
        _hideCta();
        _ctaInProgress = false;
      }
    };

    // Кастомный внешний вид — если передан
    if (widget.ctaBuilder != null) {
      return widget.ctaBuilder!(context, onPressed);
    }

    // Дефолт: одна кнопка на всю ширину.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: _ctaHeight,
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: Size(double.infinity, _ctaHeight),
            maximumSize: Size(double.infinity, _ctaHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          child: const Text('Отримати ще 15 хвилин'),
        ),
      ),
    );
  }
}
