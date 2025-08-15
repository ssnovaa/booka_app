// lib/core/network/auth_interceptor.dart
import 'dart:async';
import 'package:dio/dio.dart';

// ВНИМАНИЕ: 'auth' — подпапка текущей папки 'network'
import 'auth/auth_store.dart';

/// Интерсептор: подставляет Authorization и делает refresh при 401.
/// Одновременные запросы ждут один общий refresh.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    this.refreshPath = '/auth/refresh',
    this.headerPrefix = 'Bearer ',
  });

  final String refreshPath;
  final String headerPrefix;

  static Completer<bool>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = AuthStore.I.accessToken;
    if (token != null && options.headers['Authorization'] == null) {
      options.headers['Authorization'] = '$headerPrefix$token';
    }
    super.onRequest(options, handler);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final req = err.requestOptions;

    if (res?.statusCode != 401) {
      return super.onError(err, handler);
    }

    // не рефрешим сам refresh-запрос и когда нет refreshToken
    if (req.path.endsWith(refreshPath) || AuthStore.I.refreshToken == null) {
      return super.onError(err, handler);
    }

    try {
      // если уже идёт refresh — ждём его
      if (_refreshing != null) {
        final ok = await _refreshing!.future;
        if (!ok) return super.onError(err, handler);
        final retry = await _retryWithNewToken(req);
        return handler.resolve(retry);
      }

      // стартуем свой refresh
      _refreshing = Completer<bool>();
      final ok = await _doRefresh(req);
      _refreshing!.complete(ok);

      if (!ok) {
        await AuthStore.I.clear();
        return super.onError(err, handler);
      }

      final resp = await _retryWithNewToken(req);
      return handler.resolve(resp);
    } catch (_) {
      _refreshing?.complete(false);
      await AuthStore.I.clear();
      return super.onError(err, handler);
    } finally {
      _refreshing = null;
    }
  }

  Future<bool> _doRefresh(RequestOptions failedReq) async {
    final refreshToken = AuthStore.I.refreshToken;
    if (refreshToken == null) return false;

    // отдельный "чистый" Dio без наших интерсепторов
    final dio = Dio(BaseOptions(
      baseUrl: failedReq.baseUrl,
      connectTimeout: failedReq.connectTimeout,
      receiveTimeout: failedReq.receiveTimeout,
      sendTimeout: failedReq.sendTimeout,
    ));

    final resp = await dio.post(
      refreshPath,
      data: {'refresh_token': refreshToken},
      options: Options(
        headers: {'Authorization': '$headerPrefix$refreshToken'},
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    if (resp.statusCode == 200 && resp.data is Map) {
      final map = resp.data as Map;
      final newAccess = (map['access_token'] ?? map['accessToken']) as String?;
      final newRefresh =
          (map['refresh_token'] ?? map['refreshToken']) as String? ?? refreshToken;
      if (newAccess == null) return false;

      await AuthStore.I.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      return true;
    }
    return false;
  }

  Future<Response<dynamic>> _retryWithNewToken(RequestOptions req) async {
    final dio = Dio(BaseOptions(
      baseUrl: req.baseUrl,
      connectTimeout: req.connectTimeout,
      receiveTimeout: req.receiveTimeout,
      sendTimeout: req.sendTimeout,
    ));

    final token = AuthStore.I.accessToken;
    final headers = Map<String, dynamic>.from(req.headers);
    if (token != null) {
      headers['Authorization'] = '$headerPrefix$token';
    }

    return dio.fetch<dynamic>(req.copyWith(headers: headers));
  }
}
