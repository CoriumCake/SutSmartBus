import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient getMqttClient(String server, String clientIdentifier, int port, {bool useWebSocket = false, bool secure = false}) {
  final client = MqttServerClient.withPort(server, clientIdentifier, port);
  client.useWebSocket = useWebSocket;
  client.secure = secure;
  return client;
}
