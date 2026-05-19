class Env {
  /// 'local' or 'tunnel'. Override with --dart-define=CONNECTION_MODE=local.
  static const String connectionMode =
      String.fromEnvironment('CONNECTION_MODE', defaultValue: 'tunnel');

  /// Base API URL used in tunnel mode.
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://bus-api.catcode.tech',
  );

  /// Server IP / host used in local mode.
  static const String serverIp =
      String.fromEnvironment('SERVER_IP', defaultValue: 'localhost');

  /// API Port used in local mode.
  static const int apiPort =
      int.fromEnvironment('API_PORT', defaultValue: 8000);

  /// MQTT Broker Host.
  static const String mqttBrokerHost = String.fromEnvironment(
    'MQTT_BROKER_HOST',
    defaultValue: 'bus-mqtt.catcode.tech',
  );

  /// MQTT TCP Port.
  static const int mqttBrokerPort =
      int.fromEnvironment('MQTT_BROKER_PORT', defaultValue: 1883);

  /// MQTT WebSocket Port.
  static const int mqttWebSocketPort =
      int.fromEnvironment('MQTT_WEBSOCKET_PORT', defaultValue: 443);

  /// MQTT WebSocket path used by the hosted broker/tunnel.
  static const String mqttWebSocketPath = String.fromEnvironment(
    'MQTT_WEBSOCKET_PATH',
    defaultValue: '/mqtt',
  );

  /// Optional API key for private/admin builds only. Do not set this for
  /// public Play Store builds.
  static const String apiSecretKey =
      String.fromEnvironment('API_SECRET_KEY', defaultValue: '');

  static bool get isTunnelMode => connectionMode == 'tunnel';
}
