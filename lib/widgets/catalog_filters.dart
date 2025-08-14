import 'package:flutter/material.dart';
import '../models/genre.dart';
import '../models/author.dart';

class CatalogFilters extends StatelessWidget {
  final List<Genre> genres;
  final List<Author> authors;
  final Genre? selectedGenre;
  final Author? selectedAuthor;
  final TextEditingController searchController;
  final VoidCallback onReset;
  final ValueChanged<Genre?> onGenreChanged;
  final ValueChanged<Author?> onAuthorChanged;
  final VoidCallback onSearch;

  const CatalogFilters({
    Key? key,
    required this.genres,
    required this.authors,
    required this.selectedGenre,
    required this.selectedAuthor,
    required this.searchController,
    required this.onReset,
    required this.onGenreChanged,
    required this.onAuthorChanged,
    required this.onSearch,
  }) : super(key: key);

  InputDecoration _fieldDecoration(
      BuildContext context, {
        String? hint,
        Widget? suffixIcon,
      }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      // лупа теперь только справа, поэтому prefixIcon не используем
      suffixIcon: suffixIcon,
      // чтобы уместить 2 иконки (❌ и 🔍) без обрезки
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            // --- Поиск (лупа справа) ---
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchController,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;

                      // справа: если есть текст → [❌, 🔍], если нет → [🔍]
                      final rightIcons = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasText)
                            IconButton(
                              tooltip: 'Очистити',
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                searchController.clear();
                                onSearch();
                              },
                            ),
                          IconButton(
                            tooltip: 'Знайти',
                            icon: const Icon(Icons.search, size: 22),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              onSearch();
                            },
                          ),
                        ],
                      );

                      return TextField(
                        controller: searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          FocusScope.of(context).unfocus();
                          onSearch();
                        },
                        decoration: _fieldDecoration(
                          context,
                          hint: 'Пошук по назві або автору',
                          suffixIcon: rightIcons,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // --- Жанр / Автор + Скинути ---
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Genre>(
                    value: selectedGenre,
                    isExpanded: true,
                    decoration: _fieldDecoration(context, hint: 'Жанр'),
                    items: genres
                        .map(
                          (g) => DropdownMenuItem<Genre>(
                        value: g,
                        child: Text(g.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                        .toList(),
                    onChanged: onGenreChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<Author>(
                    value: selectedAuthor,
                    isExpanded: true,
                    decoration: _fieldDecoration(context, hint: 'Автор'),
                    items: authors
                        .map(
                          (a) => DropdownMenuItem<Author>(
                        value: a,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                        .toList(),
                    onChanged: onAuthorChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Скинути фільтри',
                  child: Ink(
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.filter_alt_off, size: 22),
                      onPressed: onReset,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
