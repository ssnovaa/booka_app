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

  static const Color _uaBlue = Color(0xFF0057B8);
  static const Color _uaYellow = Color(0xFFFFD700);
  static const Color _glowColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _updateTime();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _updateTime() {
    if (!mounted) return;

    final provider = context.read<AudioPlayerProvider>();

    if (!provider.isAdMode) {
      if (_displayText.isNotEmpty) {
        setState(() => _displayText = '');
      }
      return;
    }

    // 🔥 ЛОГІКА: Беремо реальний час, що враховує паузу (з Provider)
    final remaining = provider.timeUntilNextAd;

    // Якщо час вийшов, але ми ще граємо (чекаємо тригера реклами)
    if (remaining.inSeconds <= 0 && provider.isPlaying) {
      setState(() => _displayText = '00:00');
      return;
    }

    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    setState(() {
      _displayText = '$mm:$ss';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdMode = context.select<AudioPlayerProvider, bool>((p) => p.isAdMode);

    if (!isAdMode || _displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      // 🔥 ВАШ ДИЗАЙН: Відступи
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        // 🔥 ВАШ ДИЗАЙН: Колір 0.7
        color: Colors.black.withOpacity(0.7),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.45, 0.55, 1.0],
          colors: [
            _uaBlue.withOpacity(0.3),
            _uaBlue.withOpacity(0.3),
            _uaYellow.withOpacity(0.3),
            _uaYellow.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _glowColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 12,
            color: _glowColor,
            shadows: [
              // 🔥 ВАШ ДИЗАЙН: Розмиття 6
              Shadow(color: _glowColor, blurRadius: 6),
            ],
          ),
          const SizedBox(width: 4),
          Text(
            _displayText,
            style: const TextStyle(
              color: _glowColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 1.0,
              shadows: [
                Shadow(
                  offset: Offset(0, 0),
                  blurRadius: 2,
                  color: _glowColor,
                ),
                // 🔥 ВАШ ДИЗАЙН: Розмиття 8 (сильніше світіння)
                Shadow(
                  offset: Offset(0, 0),
                  blurRadius: 8,
                  color: _glowColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}