/// Environment configuration
/// In production, load from env file or compile-time defines
class Env {
  static const String connectionMode = String.fromEnvironment(
    'CONNECTION_MODE',
    defaultValue: 'local',
  );

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String serverIp = String.fromEnvironment(
    'SERVER_IP',
    defaultValue: 'localhost',
  );

  static const int apiPort = int.fromEnvironment(
    'API_PORT',
    defaultValue: 8000,
  );

  static const String mqttBrokerHost = String.fromEnvironment(
    'MQTT_BROKER_HOST',
    defaultValue: 'localhost',
  );

  static const int mqttBrokerPort = int.fromEnvironment(
    'MQTT_BROKER_PORT',
    defaultValue: 1883,
  );

  static const int mqttWebSocketPort = int.fromEnvironment(
    'MQTT_WS_PORT',
    defaultValue: 9001,
  );

  static const String apiSecretKey = String.fromEnvironment(
    'API_SECRET_KEY',
    defaultValue: '',
  );

  static bool get isTunnelMode => connectionMode == 'tunnel';
}
