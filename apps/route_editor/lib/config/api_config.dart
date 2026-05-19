import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'env.dart';

class ApiConfig {
  static String get baseUrl {
    if (Env.isTunnelMode) return Env.apiUrl;

    var host = Env.serverIp;
    if (!kIsWeb &&
        Platform.isAndroid &&
        (host == 'localhost' || host == '127.0.0.1')) {
      host = '10.0.2.2';
    }
    return 'http://$host:${Env.apiPort}';
  }

  static Map<String, String> get headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (Env.apiSecretKey.isNotEmpty) {
      headers['X-API-Key'] = Env.apiSecretKey;
    }
    return headers;
  }
}
