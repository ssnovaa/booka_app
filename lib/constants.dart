// constants.dart

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

String? ensureAbsoluteImageUrl(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;

  if (s.startsWith('http://') || s.startsWith('https://')) {
    return s.replaceFirst('http://', 'https://');
  }

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

String _join(String a, String b) {
  final left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  final right = b.startsWith('/') ? b.substring(1) : b;
  return '$left/$right';
}
