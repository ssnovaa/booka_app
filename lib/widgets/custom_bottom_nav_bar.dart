// lib/widgets/custom_bottom_nav_bar.dart
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

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.onOpenPlayer,
    this.onPlayerTap,
    this.onContinue,
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

  static const Color _kIconLightYellow = Color(0xFFFFF59D);
  static const Color _kRingBlue = Color(0xFF2196F3);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = theme.colorScheme.primary;
    final unselected = theme.colorScheme.onSurface.withOpacity(0.6);

    final double ring = _kBaseRing * _kOuterScale;
    final double inner = _kBaseInner * _kOuterScale * _kInnerExtra;
    final double icon = _kBaseIcon * _kOuterScale * _kInnerExtra;
    final double pad = _kBasePad * _kOuterScale;

    const double extraHit = 10.0; // расширение радиуса

    final VoidCallback openPlayer = (onOpenPlayer ?? onPlayerTap)!;

    return Material(
      color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Подборки',
                icon: Icon(
                  Icons.collections_bookmark,
                  color: currentIndex == 0 ? selected : unselected,
                ),
                onPressed: () => onTap(0),
              ),
              IconButton(
                tooltip: 'Каталог',
                icon: Icon(
                  Icons.library_books,
                  color: currentIndex == 1 ? selected : unselected,
                ),
                onPressed: () => onTap(1),
              ),

              Consumer2<AudioPlayerProvider, UserNotifier>(
                builder: (context, p, userN, _) {
                  final bool isPlaying = p.isPlaying;

                  final double childVisualSize = ring;
                  final double childHitSize = ring + 2 * extraHit;

                  return SizedBox(
                    width: ring,
                    height: _kBarHeight,
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minWidth: childHitSize,
                      maxWidth: childHitSize,
                      minHeight: childHitSize,
                      maxHeight: childHitSize,
                      child: _PlayerFab(
                        onTap: () async {
                          // важный момент: перед каждым нажатием синхронизируем тип пользователя
                          p.userType = getUserType(userN.user);
                          // если нет подготовленной сессии — вернёт false → вызовем onContinue()
                          final ok = await p.handleBottomPlayTap();
                          if (!ok) onContinue?.call();
                        },
                        onLongPress: openPlayer, // долгое нажатие — открыть полный плеер
                        isPlaying: isPlaying,
                        bgColor: theme.colorScheme.primary,
                        ringColor: _kRingBlue,
                        iconColor: _kIconLightYellow,
                        ringVisualSize: childVisualSize,
                        innerSize: inner,
                        iconSize: icon,
                        logoPadding: pad,
                        extraHitRadius: extraHit,
                        debugShowHitArea: false, // включи true для наглядности
                      ),
                    ),
                  );
                },
              ),

              IconButton(
                tooltip: 'Профіль',
                icon: Icon(
                  Icons.account_circle,
                  color: currentIndex == 3 ? selected : unselected,
                ),
                onPressed: () => onTap(3),
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

  final double ringVisualSize; // диаметр внешнего «видимого» круга
  final double extraHitRadius; // расширение радиуса хит-области
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
          // ВИЗУАЛЫ
          Align(
            alignment: Alignment.bottomCenter,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Сиреневый круг (кольцо)
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
                // Внутренняя кнопка (без собственного InkWell)
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

          // Единый кликабельный круг, центр внизу, покрывает ВСЮ область
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
