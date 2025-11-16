// lib/core/image_cache.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Кастомний менеджер кешу для зображень (для cached_network_image 3.x).
class BookaImageCacheManager extends CacheManager {
  static const key = 'booka_image_cache';

  /// Сінглтон
  static final BookaImageCacheManager instance =
  BookaImageCacheManager._internal();

  BookaImageCacheManager._internal()
      : super(
    Config(
      key,
      stalePeriod: const Duration(days: 30), // строк «придатності» файлу
      maxNrOfCacheObjects: 400,              // ліміт об’єктів у кеші
      fileService: HttpFileService(),        // стандартний HTTP-сервіс
    ),
  );

  /// Повне очищення файлового кешу картинок
  Future<void> clearAll() async {
    await emptyCache();
    if (kDebugMode) {
      debugPrint('[BookaImageCacheManager] cache cleared');
    }
  }

  /// Видалити один файл за URL
  Future<void> remove(String url) async {
    await removeFile(url);
    if (kDebugMode) {
      debugPrint('[BookaImageCacheManager] removed: $url');
    }
  }
}
