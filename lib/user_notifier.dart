// lib/user_notifier.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart';
import 'package:booka_app/core/network/auth/auth_store.dart';

import 'package:booka_app/models/user.dart';
import 'package:booka_app/repositories/profile_repository.dart';
// ⛑ Санитизация текстов ошибок
import 'package:booka_app/core/security/safe_errors.dart';

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

  /// Удобный флаг платности, если в модели есть такие признаки.
  bool get isPaid {
    final u = _user;
    if (u == null) return false;
    // Пытаемся аккуратно вытащить признак платности:
    try {
      final dyn = u as dynamic;
      final v = (dyn.isPaid ?? dyn.is_paid ?? dyn['is_paid']) == true;
      return v;
    } catch (_) {}
    return false;
  }

  /// Удобный флаг «свободный» пользователь для интеграции с тикером/списанием.
  bool get isFreeUser => isAuth && !isPaid;

  // === Секундный/минутный API для UI и rewarded/consume-потока ===

  /// Абсолютно установить секунды (например, после /profile или consume).
  void setFreeSeconds(int seconds) {
    final s = seconds.clamp(0, 0x7fffffff);
    if (s != _freeSeconds) {
      _freeSeconds = s;
      notifyListeners();
    }
  }

  /// Прибавить/убавить секунды (негатив допускается), отсечём ниже нуля.
  void addFreeSeconds(int delta) {
    final next = _freeSeconds + delta;
    final clamped = next < 0 ? 0 : (next > 0x7fffffff ? 0x7fffffff : next);
    if (clamped != _freeSeconds) {
      _freeSeconds = clamped;
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
            _user = User.fromJson(userJson);

            // ✅ Подхватываем баланс:
            // приоритет — free_seconds; затем free_minutes; затем legacy minutes
            final dynFs = userJson['free_seconds'];
            final dynFm = userJson['free_minutes'] ?? userJson['minutes'];

            if (dynFs is int) {
              _freeSeconds = dynFs < 0 ? 0 : dynFs;
            } else if (dynFm is int) {
              _freeSeconds = dynFm <= 0 ? 0 : dynFm * 60;
            } else {
              _freeSeconds = 0;
            }
          } else {
            // Иначе тянем профиль отдельно
            _user = await ProfileRepository.I.load();
            // Мягко подтянем точный баланс (не валим UI при ошибках)
            await _refreshBalanceSoft();
          }

          _isAuth = true;
          notifyListeners();
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

    try {
      final u = await ProfileRepository.I.load();
      _user = u;
      _isAuth = true;

      // Если в модели/репозитории появится прямое поле секунд — подхватите тут.
      // Параллельно мягко подтягиваем точный баланс из /profile.
      await _refreshBalanceSoft();
    } on DioException catch (e) {
      final sc = e.response?.statusCode ?? 0;
      if (sc == 401 || sc == 403) {
        await _clearAuth();
      } else {
        // Не пробрасываем «сырые» ошибки наружу
        throw AppNetworkException(
          safeErrorMessage(e, fallback: 'Не удалось загрузить профиль'),
          statusCode: sc,
        );
      }
    } catch (_) {
      await _clearAuth();
    }
    notifyListeners();
  }

  /// Публичный метод: подтянуть баланс из /profile.
  /// Вызывай после rewarded/consume, чтобы не «угадывать» локально.
  Future<void> refreshMinutesFromServer() async {
    if (!isAuth) return;
    final seconds = await _fetchSecondsOrNull();
    if (seconds != null) {
      setFreeSeconds(seconds);
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
  Future<void> _refreshBalanceSoft() async {
    try {
      final s = await _fetchSecondsOrNull();
      if (s != null) setFreeSeconds(s);
    } catch (_) {
      // молча игнорируем
    }
  }

  /// Тянет /profile и пытается извлечь ТЕКУЩИЙ баланс в секундах.
  /// Поддерживает несколько форматов ответа (free_seconds / free_minutes / minutes).
  Future<int?> _fetchSecondsOrNull() async {
    try {
      final r = await ApiClient.i().get('/profile'); // если у вас другой роут — подставьте
      final data = r.data;

      // Плоско: { ..., free_seconds: N }
      if (data is Map && data['free_seconds'] is int) {
        final fs = data['free_seconds'] as int;
        return fs < 0 ? 0 : fs;
      }

      // Плоско: { ..., free_minutes: N } → конвертируем
      if (data is Map && data['free_minutes'] is int) {
        final fm = data['free_minutes'] as int;
        return fm <= 0 ? 0 : fm * 60;
      }

      // Легаси: { ..., minutes: N } → конвертируем
      if (data is Map && data['minutes'] is int) {
        final m = data['minutes'] as int;
        return m <= 0 ? 0 : m * 60;
      }

      // Обёртка: { profile: { ... } }
      if (data is Map && data['profile'] is Map) {
        final p = data['profile'] as Map;

        if (p['free_seconds'] is int) {
          final fs = p['free_seconds'] as int;
          return fs < 0 ? 0 : fs;
        }
        if (p['free_minutes'] is int) {
          final fm = p['free_minutes'] as int;
          return fm <= 0 ? 0 : fm * 60;
        }
        if (p['minutes'] is int) {
          final m = p['minutes'] as int;
          return m <= 0 ? 0 : m * 60;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }
}
