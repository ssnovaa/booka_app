// lib/user_notifier.dart
import 'dart:async'; // 👈 ‼️ ДОБАВЛЕН ИМПОРТ
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

import 'package:booka_app/models/user.dart';
import 'package:booka_app/repositories/profile_repository.dart';
// ⛑ Санитизация текстов ошибок
import 'package:booka_app/core/security/safe_errors.dart';

// ‼️‼️‼️ ЗМІНА 1: ІМПОРТУЄМО PUSH SERVICE ‼️‼️‼️
import 'package:booka_app/core/push/push_service.dart';

/// Глобальный нотифаер пользователя + отдельный баланс «минут без рекламы».
//// ВАЖНО:
///  - Истина теперь в секундах (_freeSeconds). Минуты считаются на лету: seconds ~/ 60.
///  - Сохраняем обратную совместимость: если сервер вернёт только `free_minutes`
///    или старое поле `minutes`, корректно конвертируем их в секунды.
///  - Этот класс — единая точка правды для UI по балансу free-секунд.
class UserNotifier extends ChangeNotifier {
  User? _user;
  bool _isAuth = false;

  /// Точный остаток в секундах (источник правды — бэкенд; тут держим текущее значение для UI).
  int _freeSeconds = 0;

  // === Getters ===
  User? get user => _user;
  bool get isAuth => _isAuth;
  bool get isGuest => !_isAuth;
  String? get token => AuthStore.I.accessToken;

  /// Минуты для плашки (округление вниз).
  int get minutes => _freeSeconds ~/ 60;

  /// Секунды для точного указания/логики.
  int get freeSeconds => _freeSeconds;

  /// Удобный флаг платности (прямая совместимость со старой логикой).
  bool get isPaid {
    final u = _user;
    if (u == null) return false;
    // старый способ (оставляем для обратной совместимости):
    try {
      final dyn = u as dynamic;
      final v = (dyn.isPaid ?? dyn.is_paid ?? dyn['is_paid']) == true;
      return v;
    } catch (_) {}
    return false;
  }

  /// Новый эталонный флаг платности «на сейчас» (учитывает paid_until).
  bool get isPaidNow => _user?.isPaidNow ?? false;

  /// «Свободный» режим: авторизован и НЕ платный (с учётом paid_until).
  bool get isFreeUser => isAuth && !isPaidNow;

  // === Секундный/минутный API для UI и rewarded/consume-потока ===

  /// Абсолютно установить секунды (например, после /profile или consume).
  void setFreeSeconds(int seconds) {
    // Поглинаємо «хвіст» у 1 секунду, щоб інтерфейс гарантовано переходив у нульовий стан
    // і не зависав на 00:01 після зовнішніх оновлень (наприклад, після consume),
    // бо бекенд може повернути left=1s, а UI з перевіркою `secondsLeft > 0`
    // трактує це як наявність часу й не показує нульову плашку.
    final s = seconds.clamp(0, 0x7fffffff);
    final normalized = s <= 1 ? 0 : s;

    if (normalized != _freeSeconds) {
      _freeSeconds = normalized;
      notifyListeners();
    }
  }

  /// Прибавить/убавить секунды (негатив допускается), отсечём ниже нуля.
  void addFreeSeconds(int delta) {
    final next = _freeSeconds + delta;
    final clamped = next < 0 ? 0 : (next > 0x7fffffff ? 0x7fffffff : next);
    final normalized = clamped <= 1 ? 0 : clamped;

    if (normalized != _freeSeconds) {
      _freeSeconds = normalized;
      notifyListeners();
    }
  }

  /// ОБРАТНАЯ СОВМЕСТИМОСТЬ: установить минуты (конвертируем в секунды).
  void setMinutes(int value) {
    final seconds = (value < 0 ? 0 : value) * 60;
    setFreeSeconds(seconds);
  }

  /// ОБРАТНАЯ СОВМЕСТИМОСТЬ: добавить минуты (конвертируем в секунды).
  void addMinutes(int delta) {
    addFreeSeconds(delta * 60);
  }

  // === Auth / Profile ===

  Future<void> tryAutoLogin() async {
    if (!AuthStore.I.isLoggedIn) {
      await _clearAuth();
      notifyListeners();
      return;
    }
    await fetchCurrentUser();

    // ‼️‼️‼️ ЗМІНА 2: ПРИМУСОВО РЕЄСТРУЄМО ТОКЕН ПІСЛЯ АВТО-ЛОГІНУ ‼️‼️‼️
    // Це оновить `user_id` для токена з `null` на актуальний
    unawaited(PushService.instance.registerToken(force: true));
  }

  Future<void> checkAuth() async => tryAutoLogin();

  Future<void> loginWithEmail(String email, String password) async {
    try {
      Response r;

      try {
        r = await ApiClient.i().post('/auth/login', data: {
          'email': email,
          'password': password,
        });
      } on DioException catch (e) {
        final code = e.response?.statusCode ?? 0;
        if (code == 404 || code == 405) {
          r = await ApiClient.i().post('/login', data: {
            'email': email,
            'password': password,
          });
        } else {
          rethrow;
        }
      }

      if (r.statusCode == 200) {
        final data = r.data;

        final String? access = (data is Map)
            ? (data['access_token'] ?? data['token']) as String?
            : null;

        final String? refresh =
        (data is Map) ? (data['refresh_token'] as String?) : null;

        final String? accessExpStr =
        (data is Map) ? (data['access_expires_at'] as String?) : null;
        final DateTime? accessExp =
        (accessExpStr != null) ? DateTime.tryParse(accessExpStr) : null;

        final Map<String, dynamic>? userJson = (data is Map)
            ? (data['user'] ?? data['profile']) as Map<String, dynamic>?
            : null;

        if (access != null && access.isNotEmpty) {
          await AuthStore.I.save(
            access: access,
            refresh: refresh,
            accessExp: accessExp,
          );

          // Если бэкенд вернул профиль прямо в ответе логина — применим его.
          if (userJson != null) {
            _applyUserMap(userJson);
            _isAuth = true;

            final secondsFromPayload = _extractSecondsFromPayload(userJson);
            if (secondsFromPayload != null) {
              _freeSeconds = _clampSeconds(secondsFromPayload);
            } else {
              await _refreshBalanceSoft(force: true);
            }

            // 🔁 Мягко дотянем /auth/me для свежего is_paid/paid_until:
            await _refreshPaidStatusSoft();
          } else {
            // Иначе тянем профиль отдельно
            _user = await ProfileRepository.I.load();
            _isAuth = true;

            final cachedProfile = ProfileRepository.I.getCachedMap();
            final secondsFromCache = _extractSecondsFromPayload(cachedProfile);
            if (secondsFromCache != null) {
              _freeSeconds = _clampSeconds(secondsFromCache);
            } else {
              // Мягко подтянем точный баланс (не валим UI при ошибках)
              await _refreshBalanceSoft();
            }

            // 🔁 И обновим платность с приватного /auth/me
            await _refreshPaidStatusSoft();
          }

          notifyListeners();

          // ‼️‼️‼️ ЗМІНА 3: ПРИМУСОВО РЕЄСТРУЄМО ТОКЕН ПІСЛЯ ЛОГІНУ ‼️‼️‼️
          // Це оновить `user_id` для токена з `null` на актуальний
          unawaited(PushService.instance.registerToken(force: true));

          return;
        }
      }

      // Генерик сообщение без сырого server body
      throw AppNetworkException(
        'Не удалось войти. Попробуйте позже.',
        statusCode: r.statusCode,
      );
    } on DioException catch (e) {
      String msg = safeErrorMessage(
        e,
        fallback: 'Ошибка входа. Проверьте соединение.',
      );
      if (e.response?.statusCode == 401) {
        msg = 'Неверный email или пароль';
      }
      throw AppNetworkException(msg, statusCode: e.response?.statusCode);
    } catch (_) {
      throw AppNetworkException('Произошла ошибка. Попробуйте ещё раз.');
    }
  }

  Future<void> fetchCurrentUser() async {
    if (!AuthStore.I.isLoggedIn) {
      await _clearAuth();
      notifyListeners();
      return;
    }

    // Маємо токен — вважаємо користувача авторизованим, навіть якщо мережа лагає
    _isAuth = true;

    try {
      final u = await ProfileRepository.I.load(debugTag: 'UserNotifier.fetch');
      _user = u;
      _isAuth = true;

      final cachedProfile = ProfileRepository.I.getCachedMap();
      final secondsFromCache = _extractSecondsFromPayload(cachedProfile);
      if (secondsFromCache != null) {
        _freeSeconds = _clampSeconds(secondsFromCache);
      }

      // Паралельно м'яко підтягнемо точний баланс із /profile.
      await _refreshBalanceSoft();

      // 🔁 І дотягнемо приватний статус підписки з /auth/me
      await _refreshPaidStatusSoft();

      // ‼️‼️‼️ ЗМІНА 4: ПРИМУСОВО РЕЄСТРУЄМО ТОКЕН ПІСЛЯ ВІДНОВЛЕННЯ СЕСІЇ ‼️‼️‼️
      if (_isAuth) {
        unawaited(PushService.instance.registerToken(force: true));
      }
    } on DioException catch (e) {
      // Залишаємо авторизацію, помилку передаємо у безпечному вигляді
      final sc = e.response?.statusCode ?? 0;
      throw AppNetworkException(
        safeErrorMessage(e, fallback: 'Не удалось загрузить профиль'),
        statusCode: sc,
      );
    } on AppNetworkException catch (e) {
      // Не скидаємо токен, навіть якщо бекенд тимчасово відповів 401/403
      if (e.statusCode == 401 || e.statusCode == 403) {
        return;
      }

      throw AppNetworkException(
        e.message,
        statusCode: e.statusCode,
      );
    } catch (_) {
      // Ігноруємо, авторизацію не очищаємо
    }
    notifyListeners();
  }

  /// Публичный метод: подтянуть баланс из /profile.
  /// Вызывай после rewarded/consume, чтобы не «угадывать» локально.
  Future<void> refreshMinutesFromServer() async {
    if (!isAuth) return;
    final seconds = await _fetchSecondsOrNull(force: true);
    if (seconds != null) {
      setFreeSeconds(seconds);
    }
  }

  /// Публичный метод: гарантированно обновить платность из /auth/me.
  Future<void> refreshUserFromMe() async {
    if (!isAuth) return;
    try {
      final r = await ApiClient.i().get('/auth/me'); // Dio Response
      final data = (r is Response) ? r.data : r;
      if (data is Map) {
        _applyUserMap(Map<String, dynamic>.from(data));
        notifyListeners();
      }
    } catch (_) {
      // молча игнорируем; UI не рушим
    }
  }

  Future<void> continueAsGuest() async {
    await _clearAuth();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      final refresh = AuthStore.I.refreshToken;
      await ApiClient.i().post(
        '/auth/logout',
        data: {if (refresh != null) 'refresh_token': refresh},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
    } catch (_) {
      // намеренно игнорируем — всё равно чистим локальное состояние
    } finally {
      await _clearAuth();
      notifyListeners();
    }
  }

  // === Internal ===

  void _applyUserMap(Map<String, dynamic> json) {
    try {
      _user = User.fromJson(json);
    } catch (_) {
      // Если что-то сломалось в парсинге — не роняем приложение
    }
  }

  Future<void> _clearAuth() async {
    await AuthStore.I.clear();
    _user = null;
    _isAuth = false;
    _freeSeconds = 0; // сбрасываем локальный баланс
    try {
      ProfileRepository.I.invalidate();
    } catch (_) {}
  }

  /// Мягкий рефреш баланса (не кидает исключения наружу).
  Future<void> _refreshBalanceSoft({bool force = false}) async {
    try {
      final s = await _fetchSecondsOrNull(force: force);
      if (s != null) setFreeSeconds(s);
    } catch (_) {
      // молча игнорируем
    }
  }

  /// Мягко обновляем платность из приватного /auth/me (не бросает исключения).
  Future<void> _refreshPaidStatusSoft() async {
    if (!isAuth) return;
    try {
      final r = await ApiClient.i().get('/auth/me'); // Dio Response
      final data = (r is Response) ? r.data : r;
      if (data is Map) {
        _applyUserMap(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // ignore
    }
  }

  /// Тянет /profile и пытается извлечь ТЕКУЩИЙ баланс в секундах.
  /// Поддерживает несколько форматов ответа (free_seconds / free_minutes / minutes).
  Future<int?> _fetchSecondsOrNull({bool force = false}) async {
    try {
      final map = await ProfileRepository.I.loadMap(
        force: force,
        debugTag: force ? 'UserNotifier.balance(force)' : 'UserNotifier.balance',
      );

      return _extractSecondsFromPayload(map);
    } catch (_) {
      // ignore
    }
    return null;
  }

  /// Унифицированное извлечение баланса секунд из произвольного JSON.
  int? _extractFreeSeconds(Map<dynamic, dynamic> data) {
    for (final key in const [
      'free_seconds',
      'freeSeconds',
      'free_seconds_left',
      'freeSecondsLeft',
    ]) {
      final seconds = _parseSeconds(data[key]);
      if (seconds != null) return seconds;
    }

    for (final key in const [
      'free_minutes',
      'freeMinutes',
      'minutes',
    ]) {
      final minutes = _parseSeconds(data[key]);
      if (minutes != null) return _clampSeconds(minutes * 60);
    }

    return null;
  }

  int? _extractSecondsFromPayload(dynamic raw) {
    if (raw is Map) {
      final seconds = _extractFreeSeconds(raw);
      if (seconds != null) return seconds;

      for (final key in const ['data', 'user', 'profile']) {
        final nested = raw[key];
        if (nested is Map) {
          final nestedSeconds = _extractSecondsFromPayload(nested);
          if (nestedSeconds != null) return nestedSeconds;
        }
      }
    }
    return null;
  }

  /// Парсит значения секунд/минут, поддерживая строки, числа и null.
  int? _parseSeconds(dynamic value) {
    if (value == null) return null;

    if (value is int) return _clampSeconds(value);
    if (value is num) return _clampSeconds(value.floor());

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;

      final parsedInt = int.tryParse(trimmed);
      if (parsedInt != null) return _clampSeconds(parsedInt);

      final parsedDouble = double.tryParse(trimmed);
      if (parsedDouble != null) return _clampSeconds(parsedDouble.floor());
    }

    return null;
  }

  int _clampSeconds(int value) {
    if (value.isNegative) return 0;
    if (value > 0x7fffffff) return 0x7fffffff;
    return value;
  }
}