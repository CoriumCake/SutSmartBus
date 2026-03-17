// lib/core/config.dart
class AppConfig {
  static const String API_BASE_URL = 'https://api.catcode.tech';
  static const String MQTT_BROKER_HOST = 'mqtt.catcode.tech';
  static const int MQTT_BROKER_PORT = 1883; // Standard MQTT port
  static const int MQTT_WEBSOCKET_PORT = 9001; // MQTT over WebSockets port
  
  // !!! IMPORTANT: Replace this with your actual API key !!!
  static const String API_SECRET_KEY = 'YOUR_ACTUAL_SECRET_KEY';
}
