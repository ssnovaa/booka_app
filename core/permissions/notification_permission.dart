// lib/core/permissions/notification_permission.dart
import 'package:permission_handler/permission_handler.dart';

/// Людський стан дозволу на сповіщення.
enum NotificationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  provisional, // iOS 12+: тихий дозвіл
  unknown,
}

class NotificationPermissionService {
  /// Поточний стан дозволу на сповіщення.
  static Future<NotificationPermissionState> getStatus() async {
    final s = await Permission.notification.status;

    if (s == PermissionStatus.provisional) return NotificationPermissionState.provisional;
    if (s.isGranted) return NotificationPermissionState.granted;
    if (s.isDenied) return NotificationPermissionState.denied;
    if (s.isPermanentlyDenied) return NotificationPermissionState.permanentlyDenied;
    if (s.isRestricted) return NotificationPermissionState.restricted;
    return NotificationPermissionState.unknown;
  }

  /// Запит дозволу у користувача.
  static Future<NotificationPermissionState> request() async {
    final s = await Permission.notification.request();

    if (s == PermissionStatus.provisional) return NotificationPermissionState.provisional;
    if (s.isGranted) return NotificationPermissionState.granted;
    if (s.isDenied) return NotificationPermissionState.denied;
    if (s.isPermanentlyDenied) return NotificationPermissionState.permanentlyDenied;
    if (s.isRestricted) return NotificationPermissionState.restricted;
    return NotificationPermissionState.unknown;
  }

  /// Відкрити системні налаштування застосунку.
  static Future<bool> openSettings() => openAppSettings();
}
