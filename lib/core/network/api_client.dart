// lib/core/network/api_client.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:booka_app/constants.dart';

class ApiClient {
  static late Dio _dio;
  static bool _initialized = false;

  /// Хранилище кэша (экспортируем для ручной очистки/удаления).
  static late CacheStore cacheStore;

  /// Путь к папке файлового кэша (для отладки, может быть null на web/памяти).
  static String? cachePath;

  /// Инициализация — вызвать в main() перед использованием ApiClient.i()
  static Future<void> init({
    int fileCacheMaxSizeBytes = 128 * 1024 * 1024, // актуально только для MemCacheStore (web/fallback)
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

    // Web -> память; платформы -> файловый кэш (fallback в память)
    if (kIsWeb) {
      cacheStore = MemCacheStore(maxSize: fileCacheMaxSizeBytes);
      cachePath = null;
      if (kDebugMode) debugPrint('ApiClient: using MemCacheStore (web)');
    } else {
      try {
        final tmpDir = await getTemporaryDirectory();
        final dirPath = p.join(tmpDir.path, 'dio_cache');
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        cacheStore = FileCacheStore(dirPath); // http_cache_file_store: только путь
        cachePath = dirPath;
        if (kDebugMode) debugPrint('ApiClient: using FileCacheStore at $dirPath');
      } catch (e) {
        cacheStore = MemCacheStore(maxSize: fileCacheMaxSizeBytes);
        cachePath = null;
        if (kDebugMode) {
          debugPrint('ApiClient: using MemCacheStore (fallback). Reason: $e');
        }
      }
    }

    // Глобальные опции кэша для всех запросов (если не переопределить per-request).
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

    // Authorization interceptor — подставляем token из SharedPreferences.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('token');
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (_) {}
          handler.next(options);
        },
      ),
    );

    // Простой retry для GET (при 502/503/504).
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (err, handler) async {
          final req = err.requestOptions;
          final status = err.response?.statusCode;
          final isGet = req.method.toUpperCase() == 'GET';
          if (isGet && status != null && {502, 503, 504}.contains(status)) {
            try {
              await Future<void>.delayed(const Duration(milliseconds: 400));
              final cloneResp = await dio.fetch(req);
              return handler.resolve(cloneResp);
            } catch (_) {}
          }
          handler.next(err);
        },
      ),
    );

    // Debug-логи с пометкой HIT/MISS.
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
      throw StateError('ApiClient not initialized. Call ApiClient.init() in main() before using.');
    }
    return _dio;
  }

  /// Per-request CacheOptions (можно передавать через `.toOptions()` в Dio).
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

  /// Очистить весь кэш.
  static Future<void> clearAllCache() async {
    await cacheStore.clean();
  }

  /// Удалить кэш-конкретного запроса по path+queryParams.
  static Future<void> deleteCacheFor(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    final base = Uri.parse(BASE_URL);
    final qp = (queryParameters ?? {})
        .map((k, v) => MapEntry(k, v?.toString()));

    Uri url;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      url = Uri.parse(path).replace(queryParameters: qp);
    } else if (path.startsWith('/')) {
      url = base.replace(path: path, queryParameters: qp);
    } else {
      url = base.resolve(path).replace(queryParameters: qp);
    }

    // В 4.x builder принимает именованные параметры.
    final cacheKey = CacheOptions.defaultCacheKeyBuilder(url: url, headers: null);
    await cacheStore.delete(cacheKey);
  }

  /// ===== Отладочные утилиты для проверки кэша =====

  /// true, если ответ пришёл из кэша (а не из сети).
  static bool wasFromCache(Response r) {
    final fromNetwork = r.extra[extraFromNetworkKey] == true; // '@fromNetwork@'
    final hasKey = r.extra[extraCacheKey] != null;            // '@cache_key@'
    return hasKey && !fromNetwork;
  }

  /// Возвращает строку-пометку 'HIT(cache)' / 'MISS(net)'.
  static String cacheMark(Response r) => wasFromCache(r) ? 'HIT(cache)' : 'MISS(net)';

  /// Печать информации о папке кэша (кол-во файлов и размер).
  static Future<void> debugPrintCacheDirInfo() async {
    if (cachePath == null) {
      debugPrint('Cache dir is null (web или MemCacheStore).');
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
