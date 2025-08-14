// lib/core/image_cache.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Кастомный менеджер кеша для изображений (для cached_network_image 3.x).
class BookaImageCacheManager extends CacheManager {
  static const key = 'booka_image_cache';

  /// Синглтон
  static final BookaImageCacheManager instance =
  BookaImageCacheManager._internal();

  BookaImageCacheManager._internal()
      : super(
    Config(
      key,
      stalePeriod: const Duration(days: 30), // срок «годности» файла
      maxNrOfCacheObjects: 400,              // лимит объектов в кэше
      fileService: HttpFileService(),        // стандартный HTTP-сервис
    ),
  );

  /// Полная очистка файлового кеша картинок
  Future<void> clearAll() async {
    await emptyCache();
    if (kDebugMode) {
      debugPrint('[BookaImageCacheManager] cache cleared');
    }
  }

  /// Удалить один файл по URL
  Future<void> remove(String url) async {
    await removeFile(url);
    if (kDebugMode) {
      debugPrint('[BookaImageCacheManager] removed: $url');
    }
  }
}
