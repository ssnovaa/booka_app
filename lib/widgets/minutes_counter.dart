// lib/widgets/minutes_counter.dart
// Комментарии — русские; тексты — украинские.
// Виджет лічильника хвилин с контроллером для «пульса» (подсветка).

import 'package:flutter/material.dart';

class MinutesCounterController {
  VoidCallback? _pulse;
  void pulse() => _pulse?.call();
}

class MinutesCounter extends StatefulWidget {
  // Дозволяємо передавати або секунди, або хвилини (для сумісності).
  final int seconds;
  final MinutesCounterController? controller;
  final TextStyle? style;

  const MinutesCounter({
    super.key,
    int? seconds,
    int? minutes,
    this.controller,
    this.style,
  }) : seconds = seconds ?? (minutes ?? 0) * 60;

  @override
  State<MinutesCounter> createState() => _MinutesCounterState();
}

class _MinutesCounterState extends State<MinutesCounter>
    with SingleTickerProviderStateMixin {

  bool _pulse = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._pulse = _runPulse;
  }

  @override
  void didUpdateWidget(covariant MinutesCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller?._pulse = _runPulse;
  }

  void _runPulse() async {
    if (!mounted) return;
    setState(() => _pulse = true);
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() => _pulse = false);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w800);

    final minutes = widget.seconds ~/ 60;
    final seconds = widget.seconds % 60;

    // Текст показує хвилини, а за потреби додає секунди (< 1 хвилини)
    String label;
    if (minutes > 0 && seconds > 0) {
      label = '$minutes хв $seconds с';
    } else if (minutes > 0) {
      label = '$minutes хв';
    } else {
      label = '$seconds с';
    }

    return AnimatedScale(
      scale: _pulse ? 1.15 : 1.0,
      duration: const Duration(milliseconds: 220),
      child: Text(label, style: style),
    );
  }
}
