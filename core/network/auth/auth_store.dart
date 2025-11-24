import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  AuthStore._();
  static final AuthStore I = AuthStore._();

  String? _access;
  String? _refresh;
  DateTime? _accessExp;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  DateTime? get accessExpiresAt => _accessExp;

  bool get isLoggedIn => (_access != null && _access!.isNotEmpty) || (_refresh != null && _refresh!.isNotEmpty);
  bool get isAccessExpired {
    if (_accessExp == null) return false;
    return DateTime.now().isAfter(_accessExp!);
  }

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    _access = p.getString('auth_access_token');
    _refresh = p.getString('auth_refresh_token');
    final expStr = p.getString('auth_access_expires_at');
    _accessExp = (expStr != null && expStr.isNotEmpty) ? DateTime.tryParse(expStr) : null;
    if (kDebugMode) {
      debugPrint('AuthStore.restore(): access=${_access != null}, refresh=${_refresh != null}, exp=$_accessExp');
    }
  }

  Future<void> save({
    required String? access,
    required String? refresh,
    required DateTime? accessExp,
  }) async {
    _access = access;
    _refresh = refresh;
    _accessExp = accessExp;

    final p = await SharedPreferences.getInstance();
    if (access != null) {
      await p.setString('auth_access_token', access);
    } else {
      await p.remove('auth_access_token');
    }
    if (refresh != null) {
      await p.setString('auth_refresh_token', refresh);
    } else {
      await p.remove('auth_refresh_token');
    }
    if (accessExp != null) {
      await p.setString('auth_access_expires_at', accessExp.toIso8601String());
    } else {
      await p.remove('auth_access_expires_at');
    }
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _accessExp = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('auth_access_token');
    await p.remove('auth_refresh_token');
    await p.remove('auth_access_expires_at');
  }
}
