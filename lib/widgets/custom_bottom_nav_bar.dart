import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/models/user.dart'; // getUserType

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  final VoidCallback? onOpenPlayer;
  final VoidCallback? onPlayerTap;
  final VoidCallback? onContinue;

  /// Полный цвет иконок в круглых кнопках (НЕ FAB) — общий дефолт
  final Color? navIconColor;

  /// Отдельные цвета иконок
  final Color? genresIconColor;   // Жанры
  final Color? homeIconColor;     // Главная (Каталог)
  final Color? profileIconColor;  // Профиль

  /// Увеличение размера внутреннего круга и иконки у мини-кнопок
  final double navInnerBoost;
  final double navIconBoost;

  /// Базовые зазоры (используются, если детальные не заданы)
  final double navGap;     // дефолт для Жанры ↔︎ Главная
  final double fabSideGap; // дефолт для обеих сторон FAB

  /// Детальные зазоры (если не null — имеют приоритет)
  final double? gapGenresHome; // Жанры ↔︎ Главная
  final double? gapHomeFab;    // Главная ↔︎ FAB
  final double? gapFabProfile; // FAB ↔︎ Профиль

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.onOpenPlayer,
    this.onPlayerTap,
    this.onContinue,
    this.navIconColor,

    // индивидуальные цвета иконок по умолчанию (как в примере)
    this.genresIconColor = const Color(0xFFfffc00),
    this.homeIconColor = const Color(0xFFfffc00),
    this.profileIconColor = const Color(0xFFfffc00),

    this.navInnerBoost = 1.6,
    this.navIconBoost = 1.12,
    this.navGap = 6.0,
    this.fabSideGap = 8.0,

    // просил 30: ставлю дефолтом 30
    this.gapGenresHome = 30.0,
    this.gapHomeFab = 10.0,
    this.gapFabProfile = 30.0,
  })  : assert(onOpenPlayer != null || onPlayerTap != null,
  'Передай onOpenPlayer или onPlayerTap'),
        super(key: key);

  static const double _kBarHeight = 64.0;
  static const double _kBaseRing = 59.0;
  static const double _kBaseInner = 28.0;
  static const double _kBaseIcon = 25.0;
  static const double _kBasePad = 0.5;
  static const double _kOuterScale = 4 / 3;
  static const double _kInnerExtra = 1.10;

  static const Color _kIconLightYellow = Color(0xFFfffc00);
  static const Color _kRingBlue = Color(0xFF2196F3); // оболочка FAB

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Габариты FAB
    final double ring = _kBaseRing * _kOuterScale;
    final double inner = _kBaseInner * _kOuterScale * _kInnerExtra;
    final double icon = _kBaseIcon * _kOuterScale * _kInnerExtra;
    final double pad = _kBasePad * _kOuterScale;

    // Мини-кнопки (2/3 от FAB)
    const double scaleDown = 2 / 3;
    final double smallRing = ring * scaleDown;
    final double smallInnerBase = inner * scaleDown;
    final double smallIconBase = icon * scaleDown;
    final double smallPad = pad * scaleDown;

    // Увеличиваем только внутренний круг и иконку
    final double smallInner = smallInnerBase * navInnerBoost;
    final double smallIcon = smallIconBase * navIconBoost;

    const double extraHit = 10.0;
    final VoidCallback openPlayer = (onOpenPlayer ?? onPlayerTap)!;

    // Цвета
    final Color barColor = theme.bottomAppBarTheme.color ?? theme.colorScheme.surface;
    final bool isDark = theme.brightness == Brightness.dark;

    // В темной теме «кольцо» мини-кнопок сливается с фоном бара
    final Color miniRingColor = isDark ? barColor : theme.colorScheme.primary;

    // Фон экрана
    final Color screenBg = theme.scaffoldBackgroundColor;

    // Внутренний фон мини-кнопок:
    // - темная тема: фон экрана
    // - светлая тема: primary с прозрачностью 0.8
    final Color miniInnerColor = isDark
        ? screenBg
        : theme.colorScheme.primary.withOpacity(0.8);

    // Индивидуальные цвета иконок (цепочка подстановок)
    final Color iconGenres  = genresIconColor  ?? navIconColor ?? _kIconLightYellow;
    final Color iconHome    = homeIconColor    ?? navIconColor ?? _kIconLightYellow;
    final Color iconProfile = profileIconColor ?? navIconColor ?? _kIconLightYellow;

    // Детальные отступы (если не заданы — берем дефолтные)
    final double gh = gapGenresHome ?? navGap;     // Жанры ↔︎ Главная
    final double hf = gapHomeFab ?? fabSideGap;    // Главная ↔︎ FAB
    final double fp = gapFabProfile ?? fabSideGap; // FAB ↔︎ Профиль

    // Внутренний фон FAB:
    // - темная тема: фон экрана
    // - светлая тема: primary с прозрачностью 0.8
    final Color fabInnerColor = isDark
        ? screenBg
        : theme.colorScheme.primary.withOpacity(0.8);

    return Material(
      color: barColor,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ◀️ Жанры
              _MiniRingButton(
                tooltip: 'Жанри',
                icon: Icons.grid_view_rounded,
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
                ringVisualSize: smallRing,
                innerSize: smallInner,
                iconSize: smallIcon,
                logoPadding: smallPad,
                ringColor: miniRingColor,
                innerColor: miniInnerColor,
                iconColor: iconGenres,
              ),

              // Жанры ↔︎ Главная
              SizedBox(width: gh),

              // ⌂ Главная (Каталог)
              _MiniRingButton(
                tooltip: 'Головна — Каталог',
                icon: Icons.home_rounded,
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
                ringVisualSize: smallRing,
                innerSize: smallInner,
                iconSize: smallIcon,
                logoPadding: smallPad,
                ringColor: miniRingColor,
                innerColor: miniInnerColor,
                iconColor: iconHome,
              ),

              // Главная ↔︎ FAB
              SizedBox(width: hf),

              // ⭕ FAB
              SizedBox(
                width: ring,
                height: _kBarHeight,
                child: Consumer2<AudioPlayerProvider, UserNotifier>(
                  builder: (context, p, userN, _) {
                    final bool isPlaying = p.isPlaying;
                    final double childVisualSize = ring;
                    final double childHitSize = ring + 2 * extraHit;

                    return OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minWidth: childHitSize,
                      maxWidth: childHitSize,
                      minHeight: childHitSize,
                      maxHeight: childHitSize,
                      child: _PlayerFab(
                        onTap: () async {
                          // 1) Актуализируем тип пользователя (guest/free/paid)
                          p.userType = getUserType(userN.user);

                          // 2) Привязываем consumer и локальный секундный тикер (идемпотентно)
                          await p.ensureCreditsTickerBound();

                          // 3) Пытаемся продолжить сессию / play-pause
                          final bool started = await p.handleBottomPlayTap();

                          if (!started) {
                            // Нет активной сессии — зовем ваш «Продовжити»
                            onContinue?.call();
                            return;
                          }

                          // 4) Сразу «дожмём» реарм тикера (лечит кейс FAB на профиле)
                          p.rearmFreeSecondsTickerSafely();

                          // 5) Ещё раз страховочный «биндинг» после перехода состояний плеера
                          Future.microtask(() => p.ensureCreditsTickerBound());
                          Future.delayed(const Duration(milliseconds: 250), () {
                            p.ensureCreditsTickerBound();
                            p.rearmFreeSecondsTickerSafely();
                          });
                        },
                        onLongPress: openPlayer,
                        isPlaying: isPlaying,
                        bgColor: fabInnerColor,          // светлая тема: .withOpacity(0.8), темная: screenBg
                        ringColor: _kRingBlue,
                        iconColor: _kIconLightYellow,
                        ringVisualSize: childVisualSize,
                        innerSize: inner,
                        iconSize: icon,
                        logoPadding: pad,
                        extraHitRadius: extraHit,
                        debugShowHitArea: false,
                      ),
                    );
                  },
                ),
              ),

              // FAB ↔︎ Профиль
              SizedBox(width: fp),

              // ▶️ Профиль
              _MiniRingButton(
                tooltip: 'Профіль',
                icon: Icons.person_rounded,
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
                ringVisualSize: smallRing,
                innerSize: smallInner,
                iconSize: smallIcon,
                logoPadding: smallPad,
                ringColor: miniRingColor,
                innerColor: miniInnerColor,
                iconColor: iconProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка (НЕ FAB): увеличиваем только внутренний круг и иконку.
class _MiniRingButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  final double ringVisualSize; // внешний диаметр (НЕ изменяем)
  final double innerSize;      // увеличенный внутренний круг
  final double iconSize;       // увеличенная иконка
  final double logoPadding;
  final Color ringColor;
  final Color innerColor;
  final Color iconColor;

  const _MiniRingButton({
    required this.tooltip,
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.ringVisualSize,
    required this.innerSize,
    required this.iconSize,
    required this.logoPadding,
    required this.ringColor,
    required this.innerColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double thinRing = ringVisualSize * 0.04;
    final Color ringTint = isActive ? ringColor : ringColor.withOpacity(0.55);
    final Color hi = cs.onSurface.withOpacity(0.14);
    final Color lo = cs.onSurface.withOpacity(0.08);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkResponse(
        onTap: onTap,
        radius: ringVisualSize / 2 + 10,
        containedInkWell: false,
        child: SizedBox(
          width: ringVisualSize,
          height: ringVisualSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // внешнее «кольцо» с логотипом
              Container(
                width: ringVisualSize,
                height: ringVisualSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringTint,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(logoPadding),
                      child: Image.asset(
                        'lib/assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(thinRing),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: hi, width: 1),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(thinRing * 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: lo, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // внутренний круг + иконка (увеличенные)
              Container(
                width: innerSize,
                height: innerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: innerColor,
                ),
                child: Icon(icon, size: iconSize, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerFab extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isPlaying;
  final Color bgColor;
  final Color ringColor;
  final Color iconColor;

  final double ringVisualSize;
  final double extraHitRadius;
  final double innerSize;
  final double iconSize;
  final double logoPadding;
  final bool debugShowHitArea;

  const _PlayerFab({
    required this.onTap,
    this.onLongPress,
    required this.isPlaying,
    required this.bgColor,
    required this.ringColor,
    required this.iconColor,
    required this.ringVisualSize,
    required this.innerSize,
    required this.iconSize,
    required this.logoPadding,
    required this.extraHitRadius,
    this.debugShowHitArea = false,
  });

  @override
  Widget build(BuildContext context) {
    final double outerRadius = ringVisualSize / 2;
    final double hitDiameter = (outerRadius + extraHitRadius) * 2;

    return Semantics(
      button: true,
      label: isPlaying ? 'Пауза' : 'Відтворити',
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: ringVisualSize,
                  height: ringVisualSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(logoPadding),
                    child: Image.asset(
                      'lib/assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Container(
                  width: innerSize,
                  height: innerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bgColor,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: iconColor,
                    size: iconSize,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: hitDiameter,
              height: hitDiameter,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  onLongPress: onLongPress,
                ),
              ),
            ),
          ),
          if (debugShowHitArea)
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: hitDiameter,
                height: hitDiameter,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
