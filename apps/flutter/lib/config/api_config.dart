import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io'
    show Platform; // Still need for Android check, but must guard it
import 'env.dart';

class ApiConfig {
  static String get _normalizedMqttWebSocketPath {
    final path = Env.mqttWebSocketPath.trim();
    if (path.isEmpty || path == '/') {
      return '';
    }
    return path.startsWith('/') ? path : '/$path';
  }

  /// Base URL for HTTP API
  static String get baseUrl {
    if (Env.isTunnelMode) return Env.apiUrl;

    String host = Env.serverIp;

    // On Web, Platform.isAndroid throws Unsupported error.
    if (!kIsWeb) {
      if (Platform.isAndroid && (host == 'localhost' || host == '127.0.0.1')) {
        host = '10.0.2.2';
      }
    }

    return 'http://$host:${Env.apiPort}';
  }

  /// MQTT WebSocket URL
  static String get mqttWsUrl {
    if (Env.isTunnelMode) {
      final path = _normalizedMqttWebSocketPath;
      // Cloudflare Tunnel hostnames usually terminate TLS on 443,
      // so we only append a port when a non-default port is configured.
      if (Env.mqttWebSocketPort == 443) {
        return 'wss://${Env.mqttBrokerHost}$path';
      }
      return 'wss://${Env.mqttBrokerHost}:${Env.mqttWebSocketPort}$path';
    }

    String host =
        Env.mqttBrokerHost.isEmpty ? Env.serverIp : Env.mqttBrokerHost;

    if (!kIsWeb) {
      if (Platform.isAndroid && (host == 'localhost' || host == '127.0.0.1')) {
        host = '10.0.2.2';
      }
      return 'mqtt://$host:${Env.mqttBrokerPort}';
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
