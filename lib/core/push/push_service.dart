// lib/core/push/push_service.dart (З ВИПРАВЛЕННЯМ LateInitializationError)
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart' show Options, Headers;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart' show getUserType;

// Фоновий обробник (ізолят)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  if (message.data['type'] == 'subscription_update') {
    if (kDebugMode) {
      print('[PUSH_BG] Отримано фонове сповіщення про оновлення підписки!');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_refresh_user_status', true);
      if (kDebugMode) {
        print('[PUSH_BG] Встановлено прапор force_refresh_user_status');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[PUSH_BG] Помилка встановлення прапора SharedPreferences: $e');
      }
    }
  }
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  late final FirebaseMessaging _fcm;

  final FlutterLocalNotificationsPlugin _local =
  FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  UserNotifier? _userNotifier;

  // 🔥 FIX: Прапори стану
  bool _initializing = false;
  bool _ready = false; // Стає true, коли _fcm ініціалізовано

  String? _lastTokenSent;

  Future<void> init({
    GlobalKey<NavigatorState>? navigatorKey,
    UserNotifier? userNotifier,
  }) async {
    // Якщо вже готово або в процесі — виходимо
    if (_ready || _initializing) return;
    _initializing = true;

    _navigatorKey = navigatorKey;
    _userNotifier = userNotifier;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) print('Firebase.initializeApp (в PushService) failed: $e');
    }

    _fcm = FirebaseMessaging.instance;
    // ✅ Тепер FCM готовий до використання
    _ready = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit =
    AndroidInitializationSettings('@drawable/ic_stat_notify');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings =
    InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) => _onLocalTap(resp),
      onDidReceiveBackgroundNotificationResponse: _onLocalTap,
    );

    if (Platform.isIOS) {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        criticalAlert: false,
        provisional: false,
        carPlay: false,
      );
      if (kDebugMode) {
        print('🔔 iOS notification permission: ${settings.authorizationStatus}');
      }
    }

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidChannel = AndroidNotificationChannel(
      'booka_default',
      'Booka · Push',
      description: 'Канал за замовчуванням для push-сповіщень Booka',
      importance: Importance.high,
      showBadge: true,
      playSound: true,
      enableVibration: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final res = await Permission.notification.request();
        if (kDebugMode) {
          print('🔔 Android notification result: $res');
        }
      }
    }

    FirebaseMessaging.onMessage
        .listen((msg) => _handleRemoteMessage(msg, fromTap: false));
    FirebaseMessaging.onMessageOpenedApp
        .listen((msg) => _handleRemoteMessage(msg, fromTap: true));

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      await _handleRemoteMessage(initialMessage, fromTap: true);
    }

    // Реєстрація токена (тепер безпечно, бо _ready = true)
    await registerToken();

    _fcm.onTokenRefresh
        .listen((token) => registerToken(force: true, overrideToken: token));

    _initializing = false;
  }

  Future<void> _handleRemoteMessage(
      RemoteMessage msg, {
        required bool fromTap,
      }) async {
    final data = msg.data;
    if (kDebugMode) {
      print('[PUSH] message received: fromTap=$fromTap, data=$data');
    }

    if (data['type'] == 'subscription_update') {
      if (_userNotifier != null) {
        try {
          if (kDebugMode) {
            print('[PUSH] subscription_update → running refreshUserFromMe()');
          }
          await _userNotifier!.refreshUserFromMe();

          final ctx = _navigatorKey?.currentContext;
          if (ctx != null) {
            final u = _userNotifier!.user;
            if (u != null) {
              final audio = ctx.read<AudioPlayerProvider>();
              audio.userType = getUserType(u);
              audio.notifyListeners();
              if (kDebugMode) {
                print('[PUSH] userType updated from push -> ${audio.userType}');
              }
            }
          } else {
            if (kDebugMode) {
              print(
                  '[PUSH] no navigator context, skipped AudioPlayer update (but UserNotifier updated!)');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[PUSH] failed to refresh subscription status from push: $e');
          }
        }
      } else {
        if (kDebugMode) {
          print('[PUSH] no UserNotifier, skip subscription refresh');
        }
      }
      return;
    }

    if (fromTap) {
      _handleDeepLink(data);
    }

    if (!fromTap) {
      await _onForegroundMessage(msg);
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage msg) async {
    final notif = msg.notification;

    await _local.show(
      msg.hashCode,
      notif?.title ?? 'Booka',
      notif?.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'booka_default',
          'Booka · Push',
          channelDescription:
          'Канал за замовчуванням для push-сповіщень Booka',
          priority: Priority.high,
          importance: Importance.high,
          icon: '@drawable/ic_stat_notify',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: msg.data.isEmpty ? null : msg.data.toString(),
    );
  }

  static void _onLocalTap(NotificationResponse resp) {
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    if (_navigatorKey == null || data.isEmpty) return;

    final bookId = data['book_id'] ?? data['bookId'];
    if (bookId != null) {
      _navigatorKey!.currentState?.pushNamed(
        '/book',
        arguments: {'id': bookId},
      );
      return;
    }

    final route = data['route'];
    if (route is String && route.isNotEmpty) {
      _navigatorKey!.currentState?.pushNamed(route, arguments: data);
    }
  }

  Future<void> registerToken({bool force = false, String? overrideToken}) async {
    // 🔥 FIX: Якщо сервіс ще не готовий (ініціалізація ще йде або не почалась),
    // ми просто ігноруємо цей виклик.
    // Коли init() завершиться, він сам викличе registerToken().
    if (!_ready) return;

    try {
      final token = overrideToken ?? await _fcm.getToken();
      if (token == null) return;
      if (!force && _lastTokenSent == token) return;

      final info = await PackageInfo.fromPlatform();
      final appVersion = info.version;

      final dio = ApiClient.i();
      await dio.post(
        '/push/register',
        data: {
          'token': token,
          'platform': Platform.isAndroid
              ? 'android'
              : (Platform.isIOS ? 'ios' : 'other'),
          'app_version': appVersion,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      _lastTokenSent = token;
      if (kDebugMode) print('✅ Push token зареєстрований');
    } catch (e) {
      if (kDebugMode) print('⚠️ Не вдалося зареєструвати push-token: $e');
    }
  }
}