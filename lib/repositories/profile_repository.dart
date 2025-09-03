// lib/repositories/profile_repository.dart
import 'package:dio/dio.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/models/user.dart';

/// Единый источник профиля:
/// - склеивает параллельные запросы (single-flight)
/// - мягкий TTL, чтобы не дёргать сеть при быстрых повторах
/// - fallback /profile → /me
/// - *всегда* нормализует payload
class ProfileRepository {
  ProfileRepository._(this._dio);
  final Dio _dio;

  static ProfileRepository? _inst;
  static ProfileRepository get I => _inst ??= ProfileRepository._(ApiClient.i());

  // Кэшируем НОРМАЛИЗОВАННУЮ карту (из неё при необходимости строим User)
  Map<String, dynamic>? _cacheMap;
  DateTime? _ts;
  Future<Map<String, dynamic>>? _inflight;

  /// Сколько держим кэш «свежим» для UI-повторов.
  static const Duration _ttl = Duration(seconds: 5);

  /// Старый контракт: вернуть User (строится из нормализованной карты).
  Future<User> load({bool force = false, String? debugTag}) async {
    final map = await loadMap(force: force, debugTag: debugTag);
    final userMap = (map['user'] is Map<String, dynamic>)
        ? (map['user'] as Map<String, dynamic>)
        : map;
    return User.fromJson(userMap);
  }

  /// Новый контракт для экранов UI: вернуть нормализованный Map.
  ///
  /// Структура гарантируется:
  /// - верхний уровень содержит user-поля (`id/name/email/is_paid`)
  /// - а также сопутствующие коллекции, если они пришли с бэка:
  ///   `favorites`, `listened`, `current_listen`, `server_time`
  Future<Map<String, dynamic>> loadMap({
    bool force = false,
    String? debugTag,
  }) {
    final now = DateTime.now();

    // 1) TTL-кэш
    if (!force && _cacheMap != null && _ts != null && now.difference(_ts!) < _ttl) {
      _log('cache-hit', debugTag);
      return Future.value(_cacheMap!);
    }

    // 2) Схлопываем параллельные запросы
    if (!force && _inflight != null) {
      _log('inflight-join', debugTag);
      return _inflight!;
    }

    _log(force ? 'net-force' : 'net', debugTag);

    _inflight = _fetchMapFromApi().then((map) {
      _cacheMap = map;
      _ts = DateTime.now();
      _inflight = null;
      return map;
    }).catchError((e) {
      _inflight = null;
      throw e;
    });

    return _inflight!;
  }

  /// Принудительно обновить кэш из сети.
  Future<Map<String, dynamic>> refresh({String? debugTag}) =>
      loadMap(force: true, debugTag: debugTag);

  /// Взять кэш без сети (может быть null).
  Map<String, dynamic>? getCachedMap() => _cacheMap;

  /// Инвалидация кэша (logout и т.п.)
  void invalidate() {
    _cacheMap = null;
    _ts = null;
  }

  // ---------------- внутрянка ----------------

  Future<Map<String, dynamic>> _fetchMapFromApi() async {
    // Пытаемся /profile
    Response r = await _dio.get(
      '/profile',
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    // Если /profile отсутствует на старом бэке — пробуем /me
    if (r.statusCode == 404 || r.statusCode == 405) {
      r = await _dio.get(
        '/me',
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
    }

    if (r.statusCode != 200) {
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        message: 'Failed to fetch profile',
      );
    }

    final normalized = _normalizeToMap(_unwrapPayload(r.data));
    if (normalized == null) {
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        message: 'Bad profile payload',
      );
    }
    return normalized;
  }

  /// Распаковка типичных обёрток ответа.
  dynamic _unwrapPayload(dynamic data) {
    if (data == null) return null;
    dynamic root = data;

    // Вариант: { data: {...} }
    if (root is Map && root.length == 1 && root.containsKey('data')) {
      root = root['data'];
    }

    // Вариант: { user: {...}, favorites:[], listened:[], current_listen:... }
    if (root is Map && root['user'] is Map) {
      final Map<String, dynamic> user =
      Map<String, dynamic>.from(root['user'] as Map);

      // Поднимаем user-поля на верхний уровень и доклеиваем коллекции
      final out = <String, dynamic>{...user};

      for (final k in const [
        'favorites',
        'listened',
        'current_listen',
        'server_time',
      ]) {
        if (root[k] != null) out[k] = root[k];
      }

      // Дополнительно храним «сырой user» — вдруг где-то нужен
      out['user'] = user;
      return out;
    }

    // Вариант: уже плоский объект пользователя
    return root;
  }

  /// Унификация произвольного payload к Map<String, dynamic>.
  Map<String, dynamic>? _normalizeToMap(dynamic raw) {
    if (raw == null) return null;

    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      final m = <String, dynamic>{};
      raw.forEach((k, v) => m['$k'] = v);
      return m;
    }
    if (raw is Response) {
      return _normalizeToMap(_unwrapPayload(raw.data));
    }
    return null;
  }

  void _log(String kind, String? tag) {
    // Пример лога: PROFILE[net-force] <ProfileScreen.load>
    // ignore: avoid_print
    print('PROFILE[$kind]${tag != null ? " <$tag>" : ""}');
  }
}
