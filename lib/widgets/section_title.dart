// lib/widgets/section_title.dart
import 'package:flutter/material.dart';

/// Віджет заголовка секції.
/// Призначений для послідовного рендерингу заголовків секцій у списках/сторінках.
/// Параметр [title] — текст заголовка (передається зовні).
/// [padding] — відступ навколо заголовка (можна перевизначити).
class SectionTitle extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  const SectionTitle(
      this.title, {
        super.key,
        this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 8),
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleLarge;
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: (base ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)).copyWith(
          color: cs.onSurface.withOpacity(0.92),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
