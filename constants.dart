// lib/constants.dart
import 'package:flutter/foundation.dart' show debugPrint;

// 👇 ВИКОРИСТОВУЄМО ТИМЧАСОВИЙ ДОМЕН RAILWAY
const String BASE_ORIGIN = 'https://bookacloud-production.up.railway.app';

const String API_PATH = '/api';
const String BASE_HOST = BASE_ORIGIN;
const String BASE_URL = '$BASE_ORIGIN$API_PATH';

String apiUrl(String path, [Map<String, dynamic>? query]) {
  final base = Uri.parse(BASE_ORIGIN);
  final uri = base.replace(
    path: _join(API_PATH, path),
    queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
  );
  return uri.toString();
}

String fullResourceUrl(String relativePath, [Map<String, dynamic>? query]) {
  final base = Uri.parse(BASE_ORIGIN);
  final uri = base.replace(
    path: _join('/', relativePath),
    queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
  );
  return uri.toString();
}

String wsUrl(String path) {
  final base = Uri.parse(BASE_ORIGIN);
  return base.replace(
    scheme: 'wss',
    path: _join('/', path),
  ).toString();
}

/// Універсальна функція для формування повного URL зображення з логами.
String? ensureAbsoluteImageUrl(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;

  String? result;

  // 1. Якщо посилання вже повне (Cloudflare R2)
  if (s.startsWith('http://') || s.startsWith('https://')) {
    result = s.replaceFirst('http://', 'https://');
  } else {
    // 2. Обробка відносних шляхів
    String? fragment;
    final hashIdx = s.indexOf('#');
    if (hashIdx >= 0) {
      fragment = s.substring(hashIdx + 1);
      s = s.substring(0, hashIdx);
    }

    String? queryString;
    final qIdx = s.indexOf('?');
    if (qIdx >= 0) {
      queryString = s.substring(qIdx + 1);
      s = s.substring(0, qIdx);
    }

    s = s.replaceAll('\\', '/');
    s = s.replaceFirst(RegExp(r'^/+'), '');
    s = s.replaceAll(RegExp(r'/+'), '/');

    // ✅ ПРЕФІКС storage/ ВИДАЛЕНО, бо на R2 його немає
    var abs = fullResourceUrl(s);

    if (queryString != null && queryString.isNotEmpty) {
      abs += (abs.contains('?') ? '&' : '?') + queryString;
    }
    if (fragment != null && fragment.isNotEmpty) {
      abs += '#$fragment';
    }
    result = abs;
  }

  // 📝 ЛОГ В КОНСОЛЬ
  debugPrint('🖼️ IMAGE_URL_DEBUG: $result (raw input: $raw)');
  return result;
}

String _join(String a, String b) {
  final left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  final right = b.startsWith('/') ? b.substring(1) : b;
  return '$left/$right';
}