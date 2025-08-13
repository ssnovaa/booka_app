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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      hintText: 'Пошук по назві або автору',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      prefixIcon: const Icon(Icons.search, size: 22),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSearch(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<Genre>(
                    value: selectedGenre,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Жанр',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      isDense: true,
                    ),
                    items: genres.map((g) {
                      return DropdownMenuItem<Genre>(
                        value: g,
                        child: Text(g.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: onGenreChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<Author>(
                    value: selectedAuthor,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Автор',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      isDense: true,
                    ),
                    items: authors.map((a) {
                      return DropdownMenuItem<Author>(
                        value: a,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: onAuthorChanged,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear, size: 22),
                  tooltip: 'Скинути фільтри',
                  onPressed: onReset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
