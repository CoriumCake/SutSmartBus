import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient getMqttClient(String server, String clientIdentifier, int port, {bool useWebSocket = false, bool secure = false}) {
  return MqttBrowserClient.withPort(server, clientIdentifier, port);
}
