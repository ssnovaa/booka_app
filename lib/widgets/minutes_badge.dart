// lib/widgets/minutes_badge.dart
// Комментарии — русские. UI-строки — украинські.
// Бейдж показує зворотний відлік в форматі ММ:СС, підписаний на UserNotifier.freeSeconds.
// Ніяких ручних оновлень екранів: оновлюється поточно завдяки notifyListeners().

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:booka_app/user_notifier.dart';

class MinutesBadge extends StatelessWidget {
  const MinutesBadge({
    super.key,
    this.prefix,             // напр.: 'Залишилось: '
    this.zeroPlaceholder = '00:00',
    this.compact = false,    // true — без подложки
    this.textStyle,
  });

  final String? prefix;
  final String zeroPlaceholder;
  final bool compact;
  final TextStyle? textStyle;

  String _fmt(int secs) {
    if (secs <= 0) return zeroPlaceholder;
    final m = secs ~/ 60;
    final s = secs % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Selector<UserNotifier, int>(
      selector: (_, u) => u.freeSeconds, // ВАЖНО: seconds!
      builder: (context, secs, _) {
        final style = textStyle ?? const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        );

        final children = <Widget>[
          if (prefix != null) Text(prefix!, style: style),
          Text(_fmt(secs), style: style),
        ];

        if (compact) {
          return Row(mainAxisSize: MainAxisSize.min, children: children);
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        );
      },
    );
  }
}
