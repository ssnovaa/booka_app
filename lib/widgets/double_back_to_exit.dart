import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Оборачивает экран и перехватывает системную кнопку "Назад":
/// - первый раз: показывает SnackBar "Натисніть ще раз, щоб вийти"
/// - второй раз (до 2 сек): вихід з програми (Android), на iOS просто ігнор
class DoubleBackToExit extends StatefulWidget {
  final Widget child;
  final Duration interval;
  final String message;

  const DoubleBackToExit({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 2),
    this.message = 'Натисніть ще раз, щоб вийти',
  });

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastBack;

  Future<bool> _onWillPop() async {
    // Если можно попнуть вложенный стек — не перехватываем
    final canPop = Navigator.of(context).canPop();
    if (canPop) return true;

    final now = DateTime.now();
    if (_lastBack == null || now.difference(_lastBack!) > widget.interval) {
      _lastBack = now;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              widget.message,
              style: TextStyle(color: cs.onInverseSurface),
            ),
            backgroundColor: cs.inverseSurface,
            duration: widget.interval,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
          ),
        );
      return false; // не выходим
    }

    // Повторное нажатие в интервале — закрываем приложение на Android
    if (Platform.isAndroid) {
      await SystemNavigator.pop(); // домой
      return false;
    }
    // На iOS программный выход не делаем — просто позволим pop (если есть)
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: widget.child,
    );
  }
}
