// lib/repositories/profile_repository.dart
import 'package:dio/dio.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/models/user.dart';

/// Єдине джерело профілю:
/// - склеює паралельні запити (single-flight)
/// - м’який TTL, щоб не смикати мережу при швидких повторах
/// - fallback /profile → /me
/// - *завжди* нормалізує payload
class ProfileRepository {
  ProfileRepository._(this._dio);
  final Dio _dio;

  static ProfileRepository? _inst;
  static ProfileRepository get I => _inst ??= ProfileRepository._(ApiClient.i());

  // Кешуємо НОРМАЛІЗОВАНУ карту (з неї при потребі будуємо User)
  Map<String, dynamic>? _cacheMap;
  DateTime? _ts;
  Future<Map<String, dynamic>>? _inflight;

  /// Скільки тримаємо кеш «свіжим» для UI-повторів.
  static const Duration _ttl = Duration(seconds: 5);

  /// Старий контракт: повернути User (будується з нормалізованої карти).
  Future<User> load({bool force = false, String? debugTag}) async {
    final map = await loadMap(force: force, debugTag: debugTag);
    final userMap = (map['user'] is Map<String, dynamic>)
        ? (map['user'] as Map<String, dynamic>)
        : map;
    return User.fromJson(userMap);
  }

  /// Новий контракт для екранів UI: повернути нормалізований Map.
  ///
  /// Структура гарантується:
  /// - верхній рівень містить user-поля (`id/name/email/is_paid`)
  /// - а також супутні колекції, якщо вони прийшли з беку:
  ///   `favorites`, `listened`, `current_listen`, `server_time`
  Future<Map<String, dynamic>> loadMap({
    bool force = false,
    String? debugTag,
  }) {
    final now = DateTime.now();

    // 1) TTL-кеш
    if (!force && _cacheMap != null && _ts != null && now.difference(_ts!) < _ttl) {
      _log('cache-hit', debugTag);
      return Future.value(_cacheMap!);
    }

    // 2) Схлопуємо паралельні запити
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

  /// Примусово оновити кеш із мережі.
  Future<Map<String, dynamic>> refresh({String? debugTag}) =>
      loadMap(force: true, debugTag: debugTag);

  /// Взяти кеш без мережі (може бути null).
  Map<String, dynamic>? getCachedMap() => _cacheMap;

  /// Інвалідація кешу (logout тощо)
  void invalidate() {
    _cacheMap = null;
    _ts = null;
  }

  // ---------------- внутрішня логіка ----------------

  Future<Map<String, dynamic>> _fetchMapFromApi() async {
    // Пробуємо /profile
    Response r = await _dio.get(
      '/profile',
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    // Якщо /profile відсутній на старому беку — пробуємо /me
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
        message: 'Не вдалося отримати профіль',
      );
    }

    final normalized = _normalizeToMap(_unwrapPayload(r.data));
    if (normalized == null) {
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        message: 'Некоректний payload профілю',
      );
    }
    return normalized;
  }

  /// Розпакування типових обгорток відповіді.
  dynamic _unwrapPayload(dynamic data) {
    if (data == null) return null;
    dynamic root = data;

    // Варіант: { data: {...} }
    if (root is Map && root.length == 1 && root.containsKey('data')) {
      root = root['data'];
    }

    // Варіант: { user: {...}, favorites:[], listened:[], current_listen:... }
    if (root is Map && root['user'] is Map) {
      final Map<String, dynamic> user =
      Map<String, dynamic>.from(root['user'] as Map);

      // Піднімаємо user-поля на верхній рівень і доклеюємо колекції
      final out = <String, dynamic>{...user};

      for (final k in const [
        'favorites',
        'listened',
        'current_listen',
        'server_time',
      ]) {
        if (root[k] != null) out[k] = root[k];
      }

      // Додатково зберігаємо «сирий user» — раптом десь потрібен
      out['user'] = user;
      return out;
    }

    // Варіант: уже плаский обʼєкт користувача
    return root;
  }

  /// Уніфікація довільного payload до Map<String, dynamic>.
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
    // Приклад логу: PROFILE[net-force] <ProfileScreen.load>
    // ignore: avoid_print
    print('PROFILE[$kind]${tag != null ? " <$tag>" : ""}');
  }
}
