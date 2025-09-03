/// lib/core/push/push_service.dart
/// FCM bootstrap для Flutter (Android/iOS).
/// - init() вызывает Firebase.initializeApp(), затем лениво инициализирует FirebaseMessaging
/// - запрашивает разрешения (iOS + Android 13+)
/// - обрабатывает bg/fg сообщения
/// - регистрирует токен на бэкенде (Laravel)
///
/// В main.dart:  await PushService.instance.init(navigatorKey: _navKey);

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
  // логирование bg-сообщений при необходимости
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  // ❗ Лениво инициализируем после Firebase.initializeApp()
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

    // 1.1) Теперь можно брать instance
    _fcm = FirebaseMessaging.instance;

    // 2) BG handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3) Local notifications (foreground)
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

    // 4) iOS permissions
    if (Platform.isIOS) {
      final settings = await _fcm.requestPermission(
        alert: true, badge: true, sound: true,
        announcement: false, criticalAlert: false, provisional: false, carPlay: false,
      );
      if (kDebugMode) {
        print('🔔 iOS notification permission: ${settings.authorizationStatus}');
      }
    }

    // 5) Heads-up в fg (и на iOS презентация)
    await _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // 6) Android канал
    const androidChannel = AndroidNotificationChannel(
      'booka_default',
      'Booka · Push',
      description: 'Default channel for Booka notifications',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // 6.1) Android 13+ — runtime permission
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final res = await Permission.notification.request();
        if (kDebugMode) print('🔔 Android notification permission result: $res');
      }
    }

    // 7) Handlers
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 8) App открыт из пуша
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) _handleDeepLink(initialMessage.data);

    // 9) Регистрация токена
    await _registerToken();

    // 10) Обновление токена
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
    // разбор payload при необходимости
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
        // сервер стабильно принимает form-urlencoded
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      _lastTokenSent = token;
      if (kDebugMode) print('✅ Push token registered');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to register push token: $e');
    }
  }
}
