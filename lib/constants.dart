// constants.dart

// Основной origin (HTTPS на поддомене)
const String BASE_ORIGIN = 'https://app.booka.top';
const String API_PATH = '/api';

// Оставим старые имена, но укажем новый origin — чтобы ничего не ломать:
const String BASE_HOST = BASE_ORIGIN;
const String BASE_URL  = '$BASE_ORIGIN$API_PATH';

/// Универсальный помощник для сборки API-URL.
/// Пример: apiUrl('/abooks/29/chapters', {'page': 2})
String apiUrl(String path, [Map<String, dynamic>? query]) {
  final base = Uri.parse(BASE_ORIGIN);
  final uri = base.replace(
    path: _join(API_PATH, path),
    queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
  );
  return uri.toString();
}

/// Абсолютный URL для любых статических ресурсов (storage, covers и т.п.)
/// Пример: fullResourceUrl('storage/covers/a.jpg')
String fullResourceUrl(String relativePath, [Map<String, dynamic>? query]) {
  final base = Uri.parse(BASE_ORIGIN);
  final uri = base.replace(
    path: _join('/', relativePath),
    queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
  );
  return uri.toString();
}

/// Если используешь WebSocket
String wsUrl(String path) {
  final base = Uri.parse(BASE_ORIGIN);
  return base.replace(
    scheme: 'wss',
    path: _join('/', path),
  ).toString();
}

/// Делает абсолютный URL для обложек/миниатюр.
/// Принимает:
///   'covers/a.jpg', '/covers/a.jpg', 'storage/covers/a.jpg', '/storage/covers/a.jpg', 'http(s)://…'
/// Возвращает:
///   'https://app.booka.top/storage/covers/a.jpg'
/// Сохраняет query/fragment, если они были в исходной строке.
String? ensureAbsoluteImageUrl(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Уже абсолютный URL — возвращаем как есть.
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return s;
  }

  // Отделяем фрагмент и query, чтобы корректно собрать обратно.
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

  // Нормализуем относительный путь:
  // - меняем backslash на slash
  // - убираем ведущие слэши
  // - сводим множественные слэши
  // - если это не 'storage/...', добавляем префикс 'storage/'
  s = s.replaceAll('\\', '/');
  s = s.replaceFirst(RegExp(r'^/+'), '');
  s = s.replaceAll(RegExp(r'/+'), '/');
  if (!s.startsWith('storage/')) {
    s = 'storage/$s';
  }

  var abs = fullResourceUrl(s);
  if (queryString != null && queryString.isNotEmpty) {
    abs += (abs.contains('?') ? '&' : '?') + queryString;
  }
  if (fragment != null && fragment.isNotEmpty) {
    abs += '#$fragment';
  }
  return abs;
}

// ===== Внутренние помощники =====

String _join(String a, String b) {
  final left  = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  final right = b.startsWith('/') ? b.substring(1) : b;
  return '$left/$right';
}
