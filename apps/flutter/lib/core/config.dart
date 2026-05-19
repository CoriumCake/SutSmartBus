import '../config/api_config.dart';
import '../config/env.dart';

class AppConfig {
  static String get apiBaseUrl => ApiConfig.baseUrl;
  static String get mqttBrokerHost => Env.mqttBrokerHost;
  static int get mqttBrokerPort => Env.mqttBrokerPort;
  static int get mqttWebsocketPort => Env.mqttWebSocketPort;
  static String get apiSecretKey => Env.apiSecretKey;
}
