import 'package:mqtt_client/mqtt_client.dart';

MqttClient getMqttClient(String server, String clientIdentifier, int port, {bool useWebSocket = false, bool secure = false}) => 
    throw UnsupportedError('Cannot create a client without platform-specific implementation');
