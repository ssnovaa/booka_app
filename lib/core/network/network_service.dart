import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  // Используем google.com как надежный хост для проверки DNS и пинга.
  // Можно заменить на api.booka.ua, если хотите проверять доступность именно вашего сервера.
  static const String _checkHost = 'google.com';

  /// Проверяет наличие реального доступа в интернет
  static Future<bool> hasRealInternetAccess() async {
    try {
      // Lookup — быстрый способ проверить DNS и доступность хоста.
      final result = await InternetAddress.lookup(_checkHost)
          .timeout(const Duration(seconds: 3));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Комплексная проверка: сначала тип связи, потом реальный пинг
  static Future<bool> isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();

    // Если вообще никуда не подключены
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }

    // Если подключены к чему-то, проверяем, есть ли там реальный интернет
    return await hasRealInternetAccess();
  }
}