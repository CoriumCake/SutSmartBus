import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient getMqttClient(String server, String clientIdentifier, int port,
    {bool useWebSocket = false, bool secure = false}) {
  final client = useWebSocket
      ? MqttServerClient(server, clientIdentifier)
      : MqttServerClient.withPort(server, clientIdentifier, port);
  client.useWebSocket = useWebSocket;
  if (useWebSocket) {
    // For `ws://` / `wss://`, mqtt_client expects the full URL in the
    // server field and the port configured separately.
    client.port = port;
  } else {
    client.secure = secure;
  }
  return client;
}
