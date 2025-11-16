// lib/core/credits/credits_binder.dart
//
// НОВЫЙ УПРОЩЁННЫЙ БИНДЕР.
// Исторически тут была склейка UserNotifier ↔ AudioPlayerProvider ↔ CreditsConsumer.
// Теперь CreditsConsumer живёт внутри AudioPlayerProvider, поэтому дополнительная
// прослойка не нужна. Этот виджет — безопасная «пустышка», чтобы не ломать импорты.

import 'package:flutter/widgets.dart';

class CreditsBinder extends StatelessWidget {
  final Widget child;

  const CreditsBinder({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
