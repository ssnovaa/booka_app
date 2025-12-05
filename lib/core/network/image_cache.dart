// lib/core/image_cache.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

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
      stalePeriod:
      const Duration(days: 30), // строк «придатності» файлу
      maxNrOfCacheObjects: 400, // ліміт об’єктів у кеші
      // ⏳ Кастомний HTTP із таймаутом та ретраями для підвантаження обкладинок
      fileService: BookaImageHttpService(),
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

/// HTTP-сервіс із контрольованими таймаутами та бектреком на повтори.
class BookaImageHttpService extends HttpFileService {
  BookaImageHttpService()
      : super(
    httpClient: _TimeoutRetryClient(
      http.Client(),
      retries: 2,
      requestTimeout: const Duration(seconds: 8),
      baseDelay: const Duration(milliseconds: 350),
      backoffFactor: 1.8,
    ),
  );
}

/// Обгортка над RetryClient, що додає таймаут кожному запиту.
class _TimeoutRetryClient extends http.BaseClient {
  final http.Client _inner;
  final int retries;
  final Duration requestTimeout;
  final Duration baseDelay;
  final double backoffFactor;

  _TimeoutRetryClient(
      this._inner, {
        required this.retries,
        required this.requestTimeout,
        required this.baseDelay,
        required this.backoffFactor,
      });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final response =
        await _inner.send(_cloneRequest(request)).timeout(requestTimeout);
        // 5xx пробуємо ще раз, якщо не вичерпано спроби
        if (_shouldRetry(response) && attempt <= retries) {
          await Future.delayed(_delayFor(attempt));
          continue;
        }
        return response;
      } on Exception {
        if (attempt > retries) rethrow;
        await Future.delayed(_delayFor(attempt));
      }
    }
  }

  bool _shouldRetry(http.StreamedResponse response) => response.statusCode >= 500;

  Duration _delayFor(int attempt) {
    final ms = baseDelay.inMilliseconds * math.pow(backoffFactor, attempt - 1);
    return Duration(milliseconds: ms.round());
  }

  http.BaseRequest _cloneRequest(http.BaseRequest original) {
    if (original is http.Request) {
      final copy = http.Request(original.method, original.url)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection
        ..headers.addAll(original.headers)
        ..bodyBytes = original.bodyBytes;
      return copy;
    }

    final fallback = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..headers.addAll(original.headers);

    return fallback;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}