// lib/core/push/push_service.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui'; // 🟢 Для IsolateNameServer
import 'dart:isolate'; // 🟢 Для SendPort/ReceivePort

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

// Ім'я "порту" для зв'язку між фоном та UI
const String kPlayerControlPort = 'booka_player_control_port';

// -----------------------------------------------------------------------------
// 🔥 ФОНОВИЙ ОБРОБНИК (ІЗОЛЯТ)
// -----------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final data = message.data;
  if (kDebugMode) {
    print('[PUSH_BG] Background message received: $data');
  }

  // 🔴 1. ОБРОБКА КОМАНДИ ЗУПИНКИ (force_stop_player)
  // Ми в іншому потоці, тому шукаємо "порт" головного потоку і кричимо туди "STOP"
  if (data['action'] == 'force_stop_player') {
    if (kDebugMode) print('[PUSH_BG] 🚀 Sending STOP signal to Main Isolate...');

    final SendPort? uiPort = IsolateNameServer.lookupPortByName(kPlayerControlPort);
    if (uiPort != null) {
      uiPort.send('stop_player');
    } else {
      if (kDebugMode) print('[PUSH_BG] ⚠️ UI Port not found (App might be killed).');
    }
  }

  // 2. Оновлення підписки (існуюча логіка)
  if (data['type'] == 'subscription_update') {
    if (kDebugMode) print('[PUSH_BG] Subscription update received');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_refresh_user_status', true);
    } catch (e) {
      if (kDebugMode) print('[PUSH_BG] Prefs error: $e');
    }
  }
}

// -----------------------------------------------------------------------------
// MAIN SERVICE
// -----------------------------------------------------------------------------
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  late final FirebaseMessaging _fcm;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  GlobalKey<NavigatorState>? _navigatorKey;
  UserNotifier? _userNotifier;

  // 🔥 Порт для отримання команд від фонового ізоляту
  ReceivePort? _uiReceivePort;

  bool _initializing = false;
  bool _ready = false;
  String? _lastTokenSent;

  Future<void> init({
    GlobalKey<NavigatorState>? navigatorKey,
    UserNotifier? userNotifier,
  }) async {
    if (_ready || _initializing) return;
    _initializing = true;

    _navigatorKey = navigatorKey;
    _userNotifier = userNotifier;

    // 🟢 РЕЄСТРАЦІЯ ПОРТУ (Слухаємо команди від фону)
    _registerBackgroundPort();

    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) print('Firebase.initializeApp failed: $e');
    }

    _fcm = FirebaseMessaging.instance;
    _ready = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ... (Налаштування каналів і дозволів) ...
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) => _onLocalTap(resp),
    );

    if (Platform.isIOS) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    }

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    const androidChannel = AndroidNotificationChannel(
      'booka_default',
      'Booka · Push',
      description: 'Default channel',
      importance: Importance.high,
      showBadge: true,
      playSound: true,
      enableVibration: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    if (Platform.isAndroid) {
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    }

    // Слухачі Foreground
    FirebaseMessaging.onMessage.listen((msg) => _handleRemoteMessage(msg, fromTap: false));
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _handleRemoteMessage(msg, fromTap: true));

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      await _handleRemoteMessage(initialMessage, fromTap: true);
    }

    await registerToken();
    _fcm.onTokenRefresh.listen((token) => registerToken(force: true, overrideToken: token));

    _initializing = false;
  }

  // 🟢 Магія зв'язку: Реєструємо порт в системі, щоб фон міг його знайти
  void _registerBackgroundPort() {
    try {
      // Закриваємо старий порт, якщо був
      _uiReceivePort?.close();

      _uiReceivePort = ReceivePort();
      IsolateNameServer.removePortNameMapping(kPlayerControlPort);
      final registered = IsolateNameServer.registerPortWithName(
        _uiReceivePort!.sendPort,
        kPlayerControlPort,
      );

      if (kDebugMode) print('[PUSH] UI Port registered: $registered');

      // Слухаємо повідомлення від фонового ізоляту
      _uiReceivePort!.listen((message) {
        if (message == 'stop_player') {
          if (kDebugMode) print('[PUSH] 🛑 Received STOP signal from Background!');
          _performStopPlayer();
        }
      });
    } catch (e) {
      if (kDebugMode) print('[PUSH] Port registration error: $e');
    }
  }

  // 🟢 Метод зупинки (викликається і з foreground, і через порт з background)
  Future<void> _performStopPlayer() async {
    final ctx = _navigatorKey?.currentContext;
    if (ctx != null) {
      try {
        final audio = ctx.read<AudioPlayerProvider>();
        // Примусова пауза
        if (audio.isPlaying) {
          await audio.pause();
          if (kDebugMode) print('[PUSH] ✅ Player PAUSED successfully.');
        }
      } catch (e) {
        if (kDebugMode) print('[PUSH] Error pausing player: $e');
      }

      // Оновлюємо статус юзера, щоб показати рекламу/блокування
      if (_userNotifier != null) {
        await _userNotifier!.refreshUserFromMe();
        try {
          final u = _userNotifier!.user;
          final audio = ctx.read<AudioPlayerProvider>();
          if (u != null) {
            audio.userType = getUserType(u);
            audio.notifyListeners();
          }
        } catch (_) {}
      }
    } else {
      if (kDebugMode) print('[PUSH] Context is null, cannot stop player.');
    }
  }

  Future<void> _handleRemoteMessage(RemoteMessage msg, {required bool fromTap}) async {
    final data = msg.data;

    // 1. Обробка force_stop_player (Foreground випадок)
    if (data['action'] == 'force_stop_player') {
      if (kDebugMode) print('[PUSH] 🔥 Foreground STOP action received');
      await _performStopPlayer();
      return;
    }

    // 2. Обробка subscription_update
    if (data['type'] == 'subscription_update') {
      if (kDebugMode) print('[PUSH] Subscription update (foreground)');
      await _performStopPlayer(); // Теж оновлюємо статус
      return;
    }

    if (fromTap) {
      _handleDeepLink(data);
    }

    if (!fromTap && (msg.notification?.title != null || msg.notification?.body != null)) {
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
          priority: Priority.high,
          importance: Importance.high,
          icon: '@drawable/ic_stat_notify',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: msg.data.isEmpty ? null : msg.data.toString(),
    );
  }

  static void _onLocalTap(NotificationResponse resp) {}

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

  Future<void> registerToken({bool force = false, String? overrideToken}) async {
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
          'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
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