// lib/widgets/simple_player_bottom_sheet.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/chapter.dart';
import 'simple_player.dart';

class FullPlayerBottomSheet extends StatelessWidget {
  final String title;
  final String author;
  final String? coverUrl; // опціонально: обкладинка для фону
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
              // 1) Фоновая обложка на весь лист (с кешем и фолбэком)
              if (coverUrl != null && coverUrl!.isNotEmpty)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: coverUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    fadeInDuration: const Duration(milliseconds: 180),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    placeholder: (_, __) => const SizedBox.shrink(),
                  ),
                ),

              // 2) Размытие под «glass»
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const SizedBox(),
                ),
              ),

              // 3) Полупрозрачная поверхность (чуть прозрачнее, чтобы обложку было видно)
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

              // 4) Слабый градиент сверху/снизу для читабельности
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.06),
                          Colors.white.withOpacity(0.00),
                          Colors.white.withOpacity(0.06),
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
                    // Хендл
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

                    // Закрыть
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

                    // Сам плеер
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
