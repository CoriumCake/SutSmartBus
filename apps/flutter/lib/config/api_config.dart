import 'dart:io' show Platform;
import 'env.dart';

class ApiConfig {
  /// Base URL for HTTP API
  static String get baseUrl {
    if (Env.isTunnelMode) return Env.apiUrl;

    String host = Env.serverIp;
    // Android emulator needs 10.0.2.2 to reach host's localhost
    if (Platform.isAndroid && (host == 'localhost' || host == '127.0.0.1')) {
      host = '10.0.2.2';
    }
    return 'http://$host:${Env.apiPort}';
  }

  /// MQTT WebSocket URL
  static String get mqttWsUrl {
    if (Env.isTunnelMode) {
      // Cloudflare Tunnels use SSL (wss://) on the public domain
      return 'wss://${Env.mqttBrokerHost}:${Env.mqttWebSocketPort}';
    }

    String host = Env.mqttBrokerHost.isEmpty ? Env.serverIp : Env.mqttBrokerHost;
    if (Platform.isAndroid && (host == 'localhost' || host == '127.0.0.1')) {
      host = '10.0.2.2';
    }
    return 'ws://$host:${Env.mqttWebSocketPort}';
  }

  /// Headers for API requests
  static Map<String, String> get headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (Env.apiSecretKey.isNotEmpty) {
      h['X-API-Key'] = Env.apiSecretKey;
    }
    return h;
  }
}
