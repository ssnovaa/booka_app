import 'package:flutter/material.dart';
import '../models/chapter.dart';
import 'simple_player.dart';

class FullPlayerBottomSheet extends StatelessWidget {
  final String title;
  final String author;
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
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: Colors.black,
            child: SimplePlayer(
              bookTitle: title,
              author: author,
              chapters: chapters,
              selectedChapterId: selectedChapter.id,
              initialChapter: selectedChapter,
              onChapterSelected: onChapterSelected,
            ),
          ),
        );
      },
    );
  }
}
