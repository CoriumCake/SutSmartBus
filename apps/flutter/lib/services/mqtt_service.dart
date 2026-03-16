import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/api_config.dart';

typedef MqttMessageCallback = void Function(String topic, Map<String, dynamic> data);

class MqttService {
  MqttClient? _client;
  bool _isConnecting = false;
  MqttMessageCallback? onMessage;

  /// Topics to subscribe
  static const _topics = [
    'sut/app/bus/location',
    'sut/bus/gps/fast',
    'sut/bus/gps',
    'sut/person-detection',
    'sut/bus/+/status',
  ];

  Future<void> connect() async {
    if (_isConnecting || (_client?.connectionStatus?.state == MqttConnectionState.connected)) {
      return;
    }

    _isConnecting = true;

    try {
      _client?.disconnect();

      final wsUrl = ApiConfig.mqttWsUrl;
      final uri = Uri.parse(wsUrl);
      final clientIdentifier = 'sut_smart_bus_flutter_${DateTime.now().millisecondsSinceEpoch}';

      // For Mobile/Desktop, use MqttServerClient with WebSocket enabled
      final client = MqttServerClient.withPort(uri.host, clientIdentifier, uri.port);
      client.useWebSocket = true;
      
      _client = client
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..resubscribeOnAutoReconnect = true
        ..logging(on: false)
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected;

      await _client!.connect();
    } catch (e) {
      if (kDebugMode) {
        print('[MqttService] Connection error: $e');
      }
    } finally {
      _isConnecting = false;
    }
  }

  void _onConnected() {
    if (kDebugMode) {
      print('[MqttService] Connected to MQTT Broker');
    }

    // Subscribe to all topics
    for (final topic in _topics) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
    }

    // Listen for messages
    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final payload = msg.payload as MqttPublishMessage;
        // Use Utf8Decoder instead of MqttPublishPayload utility to avoid version-specific issues
        final payloadStr = const Utf8Decoder().convert(payload.payload.message);

        try {
          final data = jsonDecode(payloadStr) as Map<String, dynamic>;
          onMessage?.call(msg.topic, data);
        } catch (e) {
          if (kDebugMode) {
            print('[MqttService] Parse error on topic ${msg.topic}: $e');
          }
        }
      }
    });
  }

  void _onDisconnected() {
    if (kDebugMode) {
      print('[MqttService] Disconnected from MQTT Broker');
    }
  }

  void disconnect() {
    _client?.disconnect();
  }
}
