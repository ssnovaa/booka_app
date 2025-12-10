// lib/repositories/profile_repository.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/core/security/safe_errors.dart';
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

  // 🔴 НОВЕ: Контролер для сповіщень про зміни профілю (наприклад, зміна "вибраного")
  final _updateController = StreamController<void>.broadcast();

  /// Потік, на який можуть підписуватися екрани (ProfileScreen), щоб знати про зміни.
  Stream<void> get onUpdate => _updateController.stream;

  /// Викликається ззовні (наприклад, з FavoritesApi), щоб повідомити про зміни.
  void notifyUpdate() {
    _updateController.add(null);
  }

  // Кешуємо НОРМАЛІЗОВАНУ карту (з неї при потребі будуємо User)
  Map<String, dynamic>? _cacheMap;
  DateTime? _ts;
  Future<Map<String, dynamic>>? _inflight;

  /// Скільки тримаємо кеш «свіжим» для UI-повторів.
  static const Duration _ttl = Duration(seconds: 5);

  /// 🔴 НОВИЙ МЕТОД: Оптимістичне оновлення локального кешу вибраного
  /// Замість повного видалення кешу (invalidate), ми точково змінюємо список.
  /// Це дозволяє миттєво оновити UI на всіх екранах (включно з головним) без "миготіння" або втрати стану.
  void updateLocalFavorites(int bookId, bool isFavorite) {
    // Якщо кешу немає, ми нічого не можемо оновити (UI сам підтягне дані при наступному запиті)
    if (_cacheMap == null) return;

    final rawList = _cacheMap!['favorites'];
    // Створюємо копію списку, щоб мутувати її
    final List<dynamic> list = (rawList is List) ? List.from(rawList) : [];

    // 1. Спочатку видаляємо книгу зі списку (якщо вона там була)
    list.removeWhere((item) {
      if (item is int) return item == bookId;
      if (item is Map) {
        final id = item['id'] ?? item['book_id'] ?? item['bookId'];
        // Порівнюємо як рядки, щоб уникнути проблем типів (int vs String)
        return id.toString() == bookId.toString();
      }
      return false;
    });

    // 2. Якщо треба додати — додаємо мінімальний об'єкт
    if (isFavorite) {
      list.add({'id': bookId, 'book_id': bookId});
    }

    // 3. Зберігаємо оновлений список назад у кеш
    _cacheMap!['favorites'] = list;

    // 4. Сповіщаємо всі віджети (включно з BookCardWidget на головній)
    notifyUpdate();
  }

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

    _inflight = _fetchMapFromApi(debugTag: debugTag).then((map) {
      _cacheMap = map;
      _ts = DateTime.now();
      _inflight = null;
      return map;
    }).catchError((e) {
      _inflight = null;
      // Якщо мережа впала, але є валідний кеш — повертаємо його замість помилки
      if (_cacheMap != null) {
        _log('net-fallback-cache', debugTag);
        return _cacheMap!;
      }

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

  static const _retryDelays = <Duration>[
    Duration(milliseconds: 100),
    Duration(milliseconds: 300),
  ];

  Future<Map<String, dynamic>> _fetchMapFromApi({String? debugTag}) async {
    AppNetworkException? last;

    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      _log('net-attempt-${attempt + 1}', debugTag);
      try {
        return await _fetchMapFromApiOnce();
      } on AppNetworkException catch (e) {
        last = e;

        final sc = e.statusCode ?? 0;
        final transient = sc == 0 || sc == 401 || sc == 403 || sc == 408 || sc == 429 || sc >= 500;

        if (transient && attempt < _retryDelays.length) {
          _log('retry-wait-${_retryDelays[attempt].inMilliseconds}ms', debugTag);
          await Future.delayed(_retryDelays[attempt]);
          continue;
        }

        rethrow;
      }
    }

    throw last ?? AppNetworkException('Невідома помилка під час отримання профілю');
  }

  Future<Map<String, dynamic>> _fetchMapFromApiOnce() async {
    try {
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
    } on DioException catch (e) {
      // мʼяка обгортка, щоб екрани могли реагувати на 401/403 без крешів
      final sc = e.response?.statusCode;
      final msg = safeErrorMessage(
        e,
        fallback: 'Не вдалося отримати профіль',
      );
      throw AppNetworkException(msg, statusCode: sc);
    }
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