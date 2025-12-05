// lib/widgets/simple_player_bottom_sheet.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/chapter.dart';
import 'simple_player.dart';
import 'package:booka_app/widgets/loading_indicator.dart'; // ← Lottie-лоадер замість стандартного бублика

/// Повноекранний bottom sheet з плеєром.
/// Підтримує фон-обкладинку, розмиття та прозору поверхню для читабельності.
class FullPlayerBottomSheet extends StatelessWidget {
  final String title;
  final String author;
  final String? coverUrl; // опційно: обкладинка для фону
  final List<Chapter> chapters;
  final Chapter selectedChapter;
  final void Function(Chapter) onChapterSelected;

  const FullPlayerBottomSheet({
    super.key,
    required this.title,
    required this.author,
    required this.chapters,
    required this.selectedChapter,
    required this.onChapterSelected,
    this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.98,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Stack(
            children: [
              // 1) Фонова обкладинка на весь лист (якщо є)
              if (coverUrl != null && coverUrl!.isNotEmpty)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: coverUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    fadeInDuration: const Duration(milliseconds: 180),
                    // 🔄 Під час завантаження показуємо єдиний Lottie-лоадер
                    placeholder: (_, __) => const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: LoadingIndicator(size: 36),
                      ),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),

              // 2) Розмиття під «glass»
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const SizedBox(),
                ),
              ),

              // 3) Напівпрозора поверхня поверх обкладинки (щоб краще читалося)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.72),
                    border: Border(
                      top: BorderSide(color: cs.outlineVariant.withOpacity(0.25)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                ),
              ),

              // 4) Слабкий вертикальний градієнт для додаткової читабельності
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          cs.onSurface.withOpacity(0.06),
                          cs.onSurface.withOpacity(0.00),
                          cs.onSurface.withOpacity(0.06),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Контент
              SafeArea(
                top: false,
                child: Stack(
                  children: [
                    // Ручка-підказка для перетягування
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 38,
                        height: 5,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    // Кнопка закриття
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton(
                        tooltip: 'Закрити',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ),

                    // Сам плеєр всередині паддінгу
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 28 + 12, 12, 12),
                      child: Material(
                        color: Colors.transparent,
                        child: SimplePlayer(
                          bookTitle: title,
                          author: author,
                          chapters: chapters,
                          selectedChapterId: selectedChapter.id,
                          initialChapter: selectedChapter,
                          onChapterSelected: onChapterSelected,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
