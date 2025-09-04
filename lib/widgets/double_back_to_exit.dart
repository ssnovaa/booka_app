import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Обгортає екран і перехоплює системну кнопку «Назад»:
/// - перше натискання: показує SnackBar "Натисніть ще раз, щоб вийти"
/// - друге натискання (протягом інтервалу): вихід з програми на Android, на iOS — дозволяємо стандартну поведінку
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
    // Якщо можна pop-нути вкладений стек — не перехоплюємо
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
      return false; // не виходимо
    }

    // Повторне натискання в інтервалі — закриваємо додаток на Android
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
      return false;
    }
    // На iOS програмний вихід не робимо — дозволяємо pop (якщо є)
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
