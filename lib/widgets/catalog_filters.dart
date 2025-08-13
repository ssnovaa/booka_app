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
    super.key,
    required this.genres,
    required this.authors,
    this.selectedGenre,
    this.selectedAuthor,
    required this.searchController,
    required this.onReset,
    required this.onGenreChanged,
    required this.onAuthorChanged,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.white10 : Colors.grey.shade100;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: theme.scaffoldBackgroundColor, // Фильтры на фоне экрана
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Wrap(
          spacing: 8.0, // Горизонтальный отступ
          runSpacing: 8.0, // Вертикальный отступ
          children: [
            _buildSearchField(context, backgroundColor),
            _buildGenreDropdown(context, backgroundColor),
            _buildAuthorDropdown(context, backgroundColor),
            _buildResetButton(context),
          ],
        ),
      ),
    );
  }

  // Виджет поля поиска
  Widget _buildSearchField(BuildContext context, Color backgroundColor) {
    return SizedBox(
      width: double.infinity, // Занимает всю доступную ширину в строке Wrap
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          hintText: 'Поиск по названию или автору',
          prefixIcon: const Icon(Icons.search, size: 22),
          filled: true,
          fillColor: backgroundColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          isDense: true,
        ),
        onSubmitted: (_) => onSearch(),
      ),
    );
  }

  // Виджет выпадающего списка жанров
  Widget _buildGenreDropdown(BuildContext context, Color backgroundColor) {
    return DropdownButtonFormField<Genre>(
      value: selectedGenre,
      isExpanded: true,
      decoration: _dropdownDecoration('Жанр', Icons.category_outlined, backgroundColor),
      items: genres.map((g) {
        return DropdownMenuItem<Genre>(
          value: g,
          child: Text(g.name, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onGenreChanged,
    );
  }

  // Виджет выпадающего списка авторов
  Widget _buildAuthorDropdown(BuildContext context, Color backgroundColor) {
    return DropdownButtonFormField<Author>(
      value: selectedAuthor,
      isExpanded: true,
      decoration: _dropdownDecoration('Автор', Icons.person_outline, backgroundColor),
      items: authors.map((a) {
        return DropdownMenuItem<Author>(
          value: a,
          child: Text(a.name, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onAuthorChanged,
    );
  }

  // Кнопка сброса фильтров
  Widget _buildResetButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.clear_all_rounded),
      tooltip: 'Сбросить фильтры',
      onPressed: onReset,
    );
  }

  // Общая декорация для выпадающих списков
  InputDecoration _dropdownDecoration(String hint, IconData icon, Color fillColor) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 22),
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      isDense: true,
    );
  }
}
