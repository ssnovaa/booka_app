/// lib/core/push/push_service.dart
/// FCM bootstrap для Flutter (Android/iOS).
/// - init() викликає Firebase.initializeApp(), потім ліниво ініціалізує FirebaseMessaging
/// - запитує дозволи (iOS + Android 13+)
/// - обробляє bg/fg повідомлення
/// - реєструє токен на бекенді (Laravel)
///
/// У main.dart:  await PushService.instance.init(navigatorKey: _navKey);

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart' show Options, Headers;

import 'package:booka_app/core/network/api_client.dart';
import 'package:package_info_plus/package_info_plus.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // логування bg-повідомлень за потреби
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  // ❗ Ліниво ініціалізуємо після Firebase.initializeApp()
  late final FirebaseMessaging _fcm;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  bool _initialized = false;
  String? _lastTokenSent;

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialized) return;
    _initialized = true;

    _navigatorKey = navigatorKey;

    // 1) Firebase Core
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) print('Firebase.initializeApp failed: $e');
    }

    // 1.1) Тепер можна брати instance
    _fcm = FirebaseMessaging.instance;

    // 2) BG handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3) Локальні нотифікації (foreground)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) => _onLocalTap(resp),
      onDidReceiveBackgroundNotificationResponse: _onLocalTap,
    );

    // 4) iOS дозволи
    if (Platform.isIOS) {
      final settings = await _fcm.requestPermission(
        alert: true, badge: true, sound: true,
        announcement: false, criticalAlert: false, provisional: false, carPlay: false,
      );
      if (kDebugMode) {
        print('🔔 iOS notification permission: ${settings.authorizationStatus}');
      }
    }

    // 5) Heads-up у fg (і на iOS презентація)
    await _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // 6) Android канал
    const androidChannel = AndroidNotificationChannel(
      'booka_default',
      'Booka · Push',
      description: 'Канал за замовчуванням для push-сповіщень Booka',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // 6.1) Android 13+ — runtime-дозвіл
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final res = await Permission.notification.request();
        if (kDebugMode) print('🔔 Android notification permission result: $res');
      }
    }

    // 7) Обробники
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 8) App відкрито з пушу
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) _handleDeepLink(initialMessage.data);

    // 9) Реєстрація токена
    await _registerToken();

    // 10) Оновлення токена
    _fcm.onTokenRefresh.listen((token) => _registerToken(force: true, overrideToken: token));
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
          priority: Priority.high,
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: msg.data.isEmpty ? null : msg.data.toString(),
    );
  }

  void _onMessageOpenedApp(RemoteMessage msg) {
    _handleDeepLink(msg.data);
  }

  static void _onLocalTap(NotificationResponse resp) {
    // розбір payload за потреби
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    if (_navigatorKey == null || data.isEmpty) return;

    final bookId = data['book_id'] ?? data['bookId'];
    if (bookId != null) {
      _navigatorKey!.currentState?.pushNamed('/book', arguments: {'id': bookId});
      return;
    }

    final route = data['route'];
    if (route is String && route.isNotEmpty) {
      _navigatorKey!.currentState?.pushNamed(route, arguments: data);
    }
  }

  Future<void> _registerToken({bool force = false, String? overrideToken}) async {
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
          'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
          'app_version': appVersion,
        },
        // сервер стабільно приймає form-urlencoded
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      _lastTokenSent = token;
      if (kDebugMode) print('✅ Push token зареєстрований');
    } catch (e) {
      if (kDebugMode) print('⚠️ Не вдалося зареєструвати push-token: $e');
    }
  }
}
