// lib/core/network/api_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:booka_app/constants.dart';

class ApiClient {
  static Dio? _dio;

  static Dio i() {
    if (_dio == null) {
      throw StateError('ApiClient not initialized. Call ApiClient.init() in main()');
    }
    return _dio!;
  }

  static Future<void> init() async {
    final options = BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      headers: const {'Accept': 'application/json'},
      responseType: ResponseType.json,
    );

    final dio = Dio(options);

    dio.interceptors.add(InterceptorsWrapper(
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
    ));

    dio.interceptors.add(InterceptorsWrapper(
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
    ));

    if (kDebugMode) {
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) {
          debugPrint('➡️ ${o.method} ${o.uri}');
          if (o.data != null) debugPrint('body: ${o.data}');
          h.next(o);
        },
        onResponse: (r, h) {
          debugPrint('✅ ${r.statusCode} ${r.requestOptions.uri}');
          h.next(r);
        },
        onError: (e, h) {
          debugPrint('❌ ${e.response?.statusCode} ${e.requestOptions.uri}');
          debugPrint('error: ${e.message}');
          h.next(e);
        },
      ));
    }

    _dio = dio;
  }
}
