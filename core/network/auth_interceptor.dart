import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:booka_app/core/network/auth/auth_store.dart';

class AuthInterceptor extends Interceptor {
  final Dio dio; // кореневий Dio для повторних запитів (retry)
  AuthInterceptor(this.dio);

  Completer<void>? _refreshing;

  bool _isAuthRoute(RequestOptions o) {
    final p = o.path;
    return p.contains('/auth/login') || p.contains('/auth/refresh') || (o.extra['skipAuth'] == true);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_isAuthRoute(options)) return handler.next(options);

    // Якщо access протермінований — спробуємо оновити заздалегідь (лінивий preflight)
    if (AuthStore.I.isAccessExpired && (AuthStore.I.refreshToken?.isNotEmpty ?? false)) {
      await _ensureRefreshed();
    }

    final access = AuthStore.I.accessToken;
    if (access != null && access.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final req = err.requestOptions;

    final is401 = res?.statusCode == 401;
    final alreadyRetried = req.extra['__ret'] == true;

    if (!_isAuthRoute(req) && is401 && !alreadyRetried && (AuthStore.I.refreshToken?.isNotEmpty ?? false)) {
      try {
        await _ensureRefreshed();
        final access = AuthStore.I.accessToken;
        if (access != null && access.isNotEmpty) {
          final cloned = await _cloneWithAuth(req, access);
          final response = await dio.fetch(cloned);
          return handler.resolve(response);
        }
      } catch (_) {
        // помилка при refresh — падаємо далі
      }
    }
    handler.next(err);
  }

  Future<void> _ensureRefreshed() async {
    if (_refreshing != null) {
      return _refreshing!.future;
    }
    _refreshing = Completer<void>();
    try {
      await _doRefresh();
    } finally {
      _refreshing!.complete();
      _refreshing = null;
    }
  }

  Future<void> _doRefresh() async {
    final rt = AuthStore.I.refreshToken;
    if (rt == null || rt.isEmpty) return;

    try {
      final resp = await dio.post(
        '/auth/refresh',
        data: {'refresh_token': rt},
        options: Options(extra: {'skipAuth': true}), // важливо: не додавати старий access
      );

      final data = resp.data as Map<String, dynamic>;
      final newAccess = (data['access_token'] as String?) ?? '';
      final accessExpStr = data['access_expires_at'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      final accessExp = accessExpStr != null ? DateTime.tryParse(accessExpStr) : null;

      if (newAccess.isEmpty) {
        await AuthStore.I.clear();
        return;
      }

      await AuthStore.I.save(
        access: newAccess,
        refresh: newRefresh ?? rt, // сервер може присилати новий refresh — беремо його, інакше залишаємо старий
        accessExp: accessExp,
      );
      if (kDebugMode) {
        debugPrint('AuthInterceptor: token refreshed, exp=$accessExp');
      }
    } catch (e) {
      // refresh не вдався — чистимо токени (користувач стає гостем)
      await AuthStore.I.clear();
      rethrow;
    }
  }

  Future<RequestOptions> _cloneWithAuth(RequestOptions o, String access) async {
    final headers = Map<String, dynamic>.from(o.headers);
    headers['Authorization'] = 'Bearer $access';

    return RequestOptions(
      path: o.path,
      method: o.method,
      headers: headers,
      queryParameters: o.queryParameters,
      data: o.data,
      baseUrl: o.baseUrl,
      connectTimeout: o.connectTimeout,
      sendTimeout: o.sendTimeout,
      receiveTimeout: o.receiveTimeout,
      extra: {...o.extra, '__ret': true},
      contentType: o.contentType,
      responseType: o.responseType,
      followRedirects: o.followRedirects,
      listFormat: o.listFormat,
      receiveDataWhenStatusError: o.receiveDataWhenStatusError,
    );
  }
}
