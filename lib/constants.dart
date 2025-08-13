// constants.dart

const String BASE_HOST = 'http://5.61.36.242';
const String API_PATH = '/api';


// Сохраняем старую константу, чтобы не ломать существующий код:
const String BASE_URL = '$BASE_HOST$API_PATH';

// Если нужно, можно добавить функцию для получения полного URL для ресурсов вне API:
String fullResourceUrl(String relativePath) {
  return '$BASE_HOST/$relativePath';
}
