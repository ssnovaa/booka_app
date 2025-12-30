// constants.dart

// 👇 ВАЖНО: Используем ваш актуальный домен
const String BASE_ORIGIN = 'https://app.booka.top';

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

/// Универсальная функция для формирования полного URL изображения.
/// Она корректно обрабатывает как полные ссылки (Cloudflare R2),
/// так и относительные пути из старой базы данных.
String? ensureAbsoluteImageUrl(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;

  // 1. Если ссылка уже полная (начинается с http), возвращаем её как есть.
  // Это критически важно для Cloudflare R2.
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return s.replaceFirst('http://', 'https://');
  }

  // 2. Обработка относительных путей
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

  // Очищаем путь от обратных слешей и лишних начальных слешей
  s = s.replaceAll('\\', '/');
  s = s.replaceFirst(RegExp(r'^/+'), '');
  s = s.replaceAll(RegExp(r'/+'), '/');

  // 3. Логика префикса storage/
  // Если ваши файлы в Cloudflare лежат в корне бакета (например, сразу в папке covers/),
  // то проверку ниже можно закомментировать.
  // Но если ссылки на Railway по-прежнему требуют /storage/, оставляем как есть.
  if (!s.startsWith('storage/')) {
    s = 'storage/$s';
  }

  var abs = fullResourceUrl(s);

  // Восстанавливаем query-параметры и фрагменты, если они были
  if (queryString != null && queryString.isNotEmpty) {
    abs += (abs.contains('?') ? '&' : '?') + queryString;
  }
  if (fragment != null && fragment.isNotEmpty) {
    abs += '#$fragment';
  }

  return abs;
}

String _join(String a, String b) {
  final left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  final right = b.startsWith('/') ? b.substring(1) : b;
  return '$left/$right';
}