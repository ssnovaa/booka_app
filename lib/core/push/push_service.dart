/// lib/core/push/push_service.dart (З ІСПРАВЛЕННЯМИ)
/// FCM bootstrap для Flutter (Android/iOS).
/// - init() викликає Firebase.initializeApp(), потім ліниво ініціалізує FirebaseMessaging
/// - запитує дозволи (iOS + Android 13+)
/// - обробляє фонові й форграундні повідомлення
/// - реєструє токен на бекенді (Laravel)
///
/// У main.dart:  await PushService.instance.init(navigatorKey: _navKey, userNotifier: userNotifier);

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
// ‼️‼️‼️ ІМПОРТУЄМО, ПОТРІБНО ДЛЯ ФОНОВОГО ОБРОБНИКА ‼️‼️‼️
import 'package:shared_preferences/shared_preferences.dart';

import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/models/user.dart' show getUserType;

bool _isSubscriptionUpdate(Map<String, dynamic> data) {
  final type = data['type'];
  if (type == 'subscription_update') return true;

  // Деякі бекенди шлють без type, але з явним статусом підписки.
  final hasSubscriptionFields =
      data.containsKey('subscription_status') ||
          data.containsKey('subscription_state');
  return hasSubscriptionFields;
}

// ‼️‼️‼️ ЗМІНА 4: Додаємо логіку у фоновий обробник ‼️‼️‼️
// Цей обробник запускається в окремому ізоляті (isolate)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Переконуємося, що Firebase ініціалізовано
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Перевіряємо, чи це наш "тихий" push про оновлення статусу
  final data = message.data;
  if (_isSubscriptionUpdate(data)) {
    if (kDebugMode) {
      print('[PUSH_BG] Отримано фонове сповіщення про оновлення підписки!');
    }
    try {
      // Оскільки це ізолят, ми не можемо оновити UserNotifier.
      // Замість цього, ми встановлюємо прапор у SharedPreferences.
      // _LifecycleReactor у main.dart побачить цей прапор при
      // поверненні додатка у foreground.
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

  // 🇺🇦 Ліниво ініціалізуємо після Firebase.initializeApp()
  late final FirebaseMessaging _fcm;

  final FlutterLocalNotificationsPlugin _local =
  FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  // ‼️ Зберігаємо UserNotifier (з попередньої правки)
  UserNotifier? _userNotifier;

  bool _initialized = false;
  String? _lastTokenSent;

  // ‼️ Оновлюємо init (з попередньої правки)
  Future<void> init({
    GlobalKey<NavigatorState>? navigatorKey,
    UserNotifier? userNotifier,
  }) async {
    if (_initialized) return;
    _initialized = true;

    _navigatorKey = navigatorKey;
    _userNotifier = userNotifier;

    // 1) Firebase Core (вже має бути ініціалізовано в main.dart)
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) print('Firebase.initializeApp (в PushService) failed: $e');
    }

    // 1.1) Тепер можна брати instance
    _fcm = FirebaseMessaging.instance;

    // 2) Обробник фонових повідомлень
    // (вже зареєстрований у main.dart, але дублювання тут не завадить)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3) Локальні нотифікації (foreground)
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

    // 4) iOS дозволи
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

    // 5) Показ heads-up у форграунді (і презентація на iOS)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 6) Android канал (ID має збігатися з AndroidManifest.xml)
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

    // 6.1) Android 13+ — runtime-дозвіл
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final res = await Permission.notification.request();
        if (kDebugMode) {
          print('🔔 Android notification result: $res');
        }
      }
    }

    // 7) Обробники життєвого циклу повідомлень
    FirebaseMessaging.onMessage
        .listen((msg) => _handleRemoteMessage(msg, fromTap: false));
    FirebaseMessaging.onMessageOpenedApp
        .listen((msg) => _handleRemoteMessage(msg, fromTap: true));

    // 8) Якщо застосунок відкрито з пушу (термінований стан)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      await _handleRemoteMessage(initialMessage, fromTap: true);
    }

    // 9) Реєстрація токена на бекенді
    // ‼️‼️‼️ ЗМІНА 1: Викликаємо ПУБЛІЧНИЙ метод ‼️‼️‼️
    await registerToken();

    // 10) Оновлення токена
    _fcm.onTokenRefresh
    // ‼️‼️‼️ ЗМІНА 2: Викликаємо ПУБЛІЧНИЙ метод ‼️‼️‼️
        .listen((token) => registerToken(force: true, overrideToken: token));
  }

  /// Єдиний вхід для всіх RemoteMessage (foreground / tap / initial)
  // ‼️ Оновлюємо _handleRemoteMessage (з попередньої правки)
  Future<void> _handleRemoteMessage(
      RemoteMessage msg, {
        required bool fromTap,
      }) async {
    final data = msg.data;
    if (kDebugMode) {
      print('[PUSH] message received: fromTap=$fromTap, data=$data');
    }

    // 1) Реакція на зміну статусу підписки
    //    👇 Бек шле type = 'subscription_update'
    if (_isSubscriptionUpdate(data)) {
      // Більше не залежимо від `context` для *оновлення* статусу.
      if (_userNotifier != null) {
        try {
          if (kDebugMode) {
            print('[PUSH] subscription_update → running refreshUserFromMe()');
          }
          // 1. Гарантовано оновлюємо UserNotifier
          await _userNotifier!.refreshUserFromMe();

          // 2. Намагаємося оновити AudioPlayer (для реклами),
          //    ця частина все ще може використовувати context, якщо він є
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

      // ❗ Для цього сервісного пуша НЕ показуємо локальну нотифікацію
      // і не робимо диплінк.
      if (kDebugMode && msg.notification != null) {
        print('[PUSH] subscription_update містить notification — ігноруємо для користувача');
      }
      return;
    }

    // 2) Якщо користувач натиснув на повідомлення → диплінк
    if (fromTap) {
      _handleDeepLink(data);
    }

    // 3) Показ локальної нотифікації у форграунді (onMessage).
    if (!fromTap) {
      await _onForegroundMessage(msg);
    }
  }

  /// Локальне повідомлення, коли додаток у форграунді
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
          icon: '@drawable/ic_stat_notify', // 🇺🇦 Монохромна біла іконка
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: msg.data.isEmpty ? null : msg.data.toString(),
    );
  }

  static void _onLocalTap(NotificationResponse resp) {
    // 🇺🇦 Розбір payload за потреби
    // (resp.payload — це String? з msg.data.toString())
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    if (_navigatorKey == null || data.isEmpty) return;

    // каст даних може приходити як String/int — приводимо до String
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

  // ‼️‼️‼️ ЗМІНА 3: Робимо метод ПУБЛІЧНИМ (прибираємо `_`) ‼️‼️‼️
  Future<void> registerToken({bool force = false, String? overrideToken}) async {
    try {
      // ‼️ Використовуємо _fcm, який вже ініціалізовано в init()
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
        // 🇺🇦 Сервер стабільно приймає form-urlencoded
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      _lastTokenSent = token;
      if (kDebugMode) print('✅ Push token зареєстрований');
    } catch (e) {
      if (kDebugMode) print('⚠️ Не вдалося зареєструвати push-token: $e');
    }
  }
}