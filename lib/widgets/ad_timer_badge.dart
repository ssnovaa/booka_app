// lib/widgets/ad_timer_badge.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:booka_app/providers/audio_player_provider.dart';

class AdTimerBadge extends StatefulWidget {
  const AdTimerBadge({super.key});

  @override
  State<AdTimerBadge> createState() => _AdTimerBadgeState();
}

class _AdTimerBadgeState extends State<AdTimerBadge> {
  Timer? _ticker;
  String _displayText = '';

  @override
  void initState() {
    super.initState();
    // Запускаем локальный таймер для обновления UI каждую секунду
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _updateTime(); // первый расчет сразу
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _updateTime() {
    if (!mounted) return;

    final provider = context.read<AudioPlayerProvider>();

    // Если не AdMode или плеер не играет, скрываем или показываем прочерки
    if (!provider.isAdMode || !provider.isPlaying) {
      if (_displayText.isNotEmpty) {
        setState(() {
          _displayText = '';
        });
      }
      return;
    }

    final nextAd = provider.nextAdTime;
    if (nextAd == null) {
      setState(() => _displayText = '');
      return;
    }

    final now = DateTime.now();
    final remaining = nextAd.difference(now);

    // Если время вышло (или отрицательное), пишем 00:00
    if (remaining.isNegative) {
      setState(() => _displayText = 'Реклама...');
      return;
    }

    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    setState(() {
      _displayText = 'Реклама через $mm:$ss';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем изменения режима (isAdMode), чтобы виджет мог исчезнуть
    final isAdMode = context.select<AudioPlayerProvider, bool>((p) => p.isAdMode);

    if (!isAdMode || _displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        _displayText,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 10, // Маленький шрифт
        ),
      ),
    );
  }
}