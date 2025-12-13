// lib/core/network/api_client.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:booka_app/constants.dart';

class ApiClient {
  static late Dio _dio;
  static bool _initialized = false;

  /// Сховище кешу (експортуємо для ручного очищення/видалення).
  static late CacheStore cacheStore;

  /// Шлях до папки файлового кешу (для відладки).
  static String? cachePath;

  /// Ініціалізація — викликати в main() перед використанням ApiClient.i()
  static Future<void> init({
    Duration defaultMaxStale = const Duration(hours: 12),
  }) async {
    if (_initialized) return;

    final options = BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      headers: const {'Accept': 'application/json'},
      responseType: ResponseType.json,
    );

    final dio = Dio(options);

    // Файловий кеш (Android/iOS). Без MemCacheStore, щоб уникнути помилки імпорту.
    try {
      final tmpDir = await getTemporaryDirectory();
      final dirPath = p.join(tmpDir.path, 'dio_cache');
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      cacheStore = FileCacheStore(dirPath);
      cachePath = dirPath;
      if (kDebugMode) debugPrint('ApiClient: using FileCacheStore at $dirPath');
    } catch (e) {
      // Фолбек: використовуємо системний temp; якщо і він упаде — пробросимо виняток.
      final altPath = p.join(Directory.systemTemp.path, 'dio_cache_fallback');
      final dir = Directory(altPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      cacheStore = FileCacheStore(altPath);
      cachePath = altPath;
      if (kDebugMode) {
        debugPrint('ApiClient: FileCacheStore fallback at $altPath. Причина: $e');
      }
    }

    // Глобальні опції кешу для всіх запитів (якщо не перевизначити per-request).
    final defaultCacheOptions = CacheOptions(
      store: cacheStore,
      policy: CachePolicy.request,
      hitCacheOnErrorCodes: const [500, 502, 503, 504],
      hitCacheOnNetworkFailure: true,
      maxStale: defaultMaxStale,
      priority: CachePriority.normal,
      allowPostMethod: false,
    );

    dio.interceptors.add(DioCacheInterceptor(options: defaultCacheOptions));

    // ⚠️ Немає ручного Authorization-інтерсептора.
    // Актуальна авторизація додається через AuthInterceptor (див. EntryScreen).

    // Простий retry: таймаути для всіх запитів, 502/503/504 для GET.
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (err, handler) async {
          final req = err.requestOptions;
          final status = err.response?.statusCode;
          final isGet = req.method.toUpperCase() == 'GET';
          const retryKey = '_retry_attempt';
          const maxRetries = 2;
          final attempt = (req.extra[retryKey] as int?) ?? 0;
          final isTimeout = err.type == DioExceptionType.connectionTimeout ||
              err.type == DioExceptionType.receiveTimeout ||
              err.type == DioExceptionType.sendTimeout;
          final shouldRetryStatus =
              isGet && status != null && {502, 503, 504}.contains(status);
          if ((isTimeout || shouldRetryStatus) && attempt < maxRetries) {
            try {
              req.extra[retryKey] = attempt + 1;
              await Future<void>.delayed(
                  Duration(milliseconds: 200 * (attempt + 1)));
              final cloneResp = await dio.fetch(req);
              return handler.resolve(cloneResp);
            } catch (_) {}
          }
          handler.next(err);
        },
      ),
    );

    // Debug-логи з позначкою HIT/MISS.
    if (kDebugMode) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            debugPrint('➡️ ${o.method} ${o.uri}');
            if (o.data != null) debugPrint('body: ${o.data}');
            h.next(o);
          },
          onResponse: (r, h) {
            final mark = cacheMark(r);
            debugPrint('✅ [$mark] ${r.statusCode} ${r.requestOptions.uri}');
            h.next(r);
          },
          onError: (e, h) {
            debugPrint('❌ ${e.response?.statusCode} ${e.requestOptions.uri} — ${e.message}');
            h.next(e);
          },
        ),
      );
    }

    _dio = dio;
    _initialized = true;
  }

  static Dio i() {
    if (!_initialized) {
      throw StateError('ApiClient не ініціалізований. Викличте ApiClient.init() у main() перед використанням.');
    }
    return _dio;
  }

  /// Per-request CacheOptions (можна передавати через `.toOptions()` у Dio).
  static CacheOptions cacheOptions({
    CachePolicy policy = CachePolicy.request,
    Duration? maxStale,
    List<int>? hitCacheOnErrorCodes,
    bool hitCacheOnNetworkFailure = true,
    CachePriority priority = CachePriority.normal,
    bool allowPostMethod = false,
  }) {
    return CacheOptions(
      store: cacheStore,
      policy: policy,
      maxStale: maxStale ?? const Duration(hours: 12),
      hitCacheOnErrorCodes: hitCacheOnErrorCodes ?? const [500, 502, 503, 504],
      hitCacheOnNetworkFailure: hitCacheOnNetworkFailure,
      priority: priority,
      allowPostMethod: allowPostMethod,
    );
  }

  /// Очистити весь кеш.
  static Future<void> clearAllCache() async {
    await cacheStore.clean();
  }

  /// Видалити кеш конкретного запиту по path+queryParams.
  static Future<void> deleteCacheFor(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    final base = Uri.parse(BASE_URL);
    final qp = (queryParameters ?? {}).map((k, v) => MapEntry(k, v?.toString()));

    Uri url;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      url = Uri.parse(path).replace(queryParameters: qp);
    } else if (path.startsWith('/')) {
      url = base.replace(path: path, queryParameters: qp);
    } else {
      url = base.resolve(path).replace(queryParameters: qp);
    }

    final cacheKey = CacheOptions.defaultCacheKeyBuilder(url: url, headers: null);
    await cacheStore.delete(cacheKey);
  }

  /// ===== Відлагоджувальні утиліти для перевірки кешу =====

  /// true, якщо відповідь прийшла з кешу (а не з мережі).
  static bool wasFromCache(Response r) {
    final fromNetwork = r.extra[extraFromNetworkKey] == true; // '@fromNetwork@'
    final hasKey = r.extra[extraCacheKey] != null;            // '@cache_key@'
    return hasKey && !fromNetwork;
  }

  /// Повертає рядок-позначку 'HIT(cache)' / 'MISS(net)'.
  static String cacheMark(Response r) => wasFromCache(r) ? 'HIT(cache)' : 'MISS(net)';

  /// Друк інформації про папку кешу (кількість файлів і розмір).
  static Future<void> debugPrintCacheDirInfo() async {
    if (cachePath == null) {
      debugPrint('Cache dir is null.');
      return;
    }
    final dir = Directory(cachePath!);
    if (!await dir.exists()) {
      debugPrint('Cache dir not found: $cachePath');
      return;
    }
    int files = 0;
    int bytes = 0;
    await for (final ent in dir.list(recursive: true, followLinks: false)) {
      if (ent is File) {
        files++;
        bytes += await ent.length();
      }
    }
    debugPrint('📦 Cache dir: $files files, ${(bytes / 1024).toStringAsFixed(1)} KB at $cachePath');
  }
}