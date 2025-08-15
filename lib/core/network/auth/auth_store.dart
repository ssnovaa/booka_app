// lib/core/network/auth/auth_store.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Простое хранилище токенов на базе SharedPreferences.
/// Если понадобится secure-хранилище — интерфейс можно оставить, а реализацию заменить.
class AuthStore {
  AuthStore._();
  static final AuthStore I = AuthStore._();

  static const _kAccess = 'auth_access_token';
  static const _kRefresh = 'auth_refresh_token';
  static const _kExpiresAt = 'auth_expires_at'; // millis since epoch (optional)

  String? _access;
  String? _refresh;
  String? _expiresAtMs;

  Future<void> restore() async {
    final sp = await SharedPreferences.getInstance();
    _access = sp.getString(_kAccess);
    _refresh = sp.getString(_kRefresh);
    _expiresAtMs = sp.getString(_kExpiresAt);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? expiresAt,
  }) async {
    final sp = await SharedPreferences.getInstance();
    _access = accessToken;
    _refresh = refreshToken;
    _expiresAtMs = expiresAt?.millisecondsSinceEpoch.toString();

    await sp.setString(_kAccess, accessToken);
    await sp.setString(_kRefresh, refreshToken);
    if (_expiresAtMs != null) {
      await sp.setString(_kExpiresAt, _expiresAtMs!);
    }
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    _access = null;
    _refresh = null;
    _expiresAtMs = null;
    await sp.remove(_kAccess);
    await sp.remove(_kRefresh);
    await sp.remove(_kExpiresAt);
  }

  String? get accessToken => _access;
  String? get refreshToken => _refresh;

  DateTime? get expiresAt {
    if (_expiresAtMs == null) return null;
    final ms = int.tryParse(_expiresAtMs!);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get hasTokens => accessToken != null && refreshToken != null;
}
