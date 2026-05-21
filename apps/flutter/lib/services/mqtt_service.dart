import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../config/api_config.dart';
import 'mqtt_client_factory.dart';

typedef MqttMessageCallback = void Function(
    String topic, Map<String, dynamic> data);
typedef CamCountCallback = void Function(int count);

const _camCountTopic = 'sut/esp32_cam/count';
const _doorCountTopic = 'bus/door/count';

class MqttService {
  MqttClient? _client;
  bool _isConnecting = false;
  MqttMessageCallback? onMessage;

  final _statusController = StreamController<MqttConnectionState>.broadcast();
  Stream<MqttConnectionState> get statusStream => _statusController.stream;
  MqttConnectionState get currentState =>
      _client?.connectionStatus?.state ?? MqttConnectionState.disconnected;

  /// Callback registered by [subscribeToCamCount].
  CamCountCallback? _camCountCallback;

  /// Topics to subscribe
  static const _topics = [
    'sut/app/bus/location',
    'sut/bus/gps/fast',
    'sut/bus/gps',
    'sut/person-detection',
    _doorCountTopic,
    'sut/bus/+/status',
  ];

  Future<void> connect() async {
    if (_isConnecting ||
        (_client?.connectionStatus?.state == MqttConnectionState.connected)) {
      return;
    }

    _isConnecting = true;

    try {
      _client?.disconnect();

      final wsUrl = ApiConfig.mqttWsUrl;
      final uri = Uri.parse(wsUrl);
      final effectivePort = uri.hasPort
          ? uri.port
          : (uri.scheme == 'wss' || uri.scheme == 'https' ? 443 : 80);
      final clientIdentifier =
          'sut_smart_bus_flutter_${DateTime.now().millisecondsSinceEpoch}';

      // Use the platform-agnostic factory
      final client = getMqttClient(wsUrl, clientIdentifier, effectivePort,
          useWebSocket: true, secure: uri.scheme == 'wss');

      _client = client
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..resubscribeOnAutoReconnect = true
        // Many hosted MQTT-over-WebSocket brokers expect the explicit `mqtt`
        // subprotocol during the WS handshake.
        ..websocketProtocols = MqttClientConstants.protocolsSingleDefault
        ..logging(on: false)
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected;

      _client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientIdentifier)
          .startClean();

      _statusController.add(MqttConnectionState.connecting);
      if (kDebugMode) {
        debugPrint(
          '[MqttService] Connecting to $wsUrl '
          '(scheme=${uri.scheme}, host=${uri.host}, port=$effectivePort, path=${uri.path})',
        );
      }
      await _client!.connect();
      if (kDebugMode && _client!.connectionStatus != null) {
        debugPrint(
          '[MqttService] Connect result: '
          '${_client!.connectionStatus!.state} '
          'code=${_client!.connectionStatus!.returnCode}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MqttService] Connection error: $e');
      }
    } finally {
      _isConnecting = false;
    }
  }

  void _onConnected() {
    if (kDebugMode) {
      debugPrint('[MqttService] Connected to MQTT Broker');
    }
    _statusController.add(MqttConnectionState.connected);

    // Subscribe to all topics
    for (final topic in _topics) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
    }
    if (_camCountCallback != null) {
      _client!.subscribe(_camCountTopic, MqttQos.atMostOnce);
    }

    // Listen for messages
    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final payload = msg.payload as MqttPublishMessage;
        final payloadStr = const Utf8Decoder().convert(payload.payload.message);

        try {
          final data = jsonDecode(payloadStr) as Map<String, dynamic>;
          // Route ESP32-CAM count messages to the dedicated callback.
          if ((msg.topic == _camCountTopic || msg.topic == _doorCountTopic) &&
              _camCountCallback != null) {
            final count = _parseCount(data['count'] ?? data['person_count']);
            if (count != null) _camCountCallback!(count);
          }
          if (msg.topic != _camCountTopic) {
            onMessage?.call(msg.topic, data);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[MqttService] Parse error on topic ${msg.topic}: $e');
          }
        }
      }
    });
  }

  void _onDisconnected() {
    if (kDebugMode) {
      final status = _client?.connectionStatus;
      debugPrint(
        '[MqttService] Disconnected from MQTT Broker '
        '(state=${status?.state}, code=${status?.returnCode})',
      );
    }
    _statusController.add(MqttConnectionState.disconnected);
  }

  void disconnect() {
    _client?.disconnect();
  }

  /// Subscribe to [_camCountTopic] and forward parsed counts to [onCount].
  void subscribeToCamCount(CamCountCallback onCount) {
    _camCountCallback = onCount;
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client!.subscribe(_camCountTopic, MqttQos.atMostOnce);
    }
    // If not yet connected the topic will be subscribed in _onConnected
    // because autoReconnect + resubscribeOnAutoReconnect are both true;
    // for the initial connection we explicitly guard in _onConnected.
  }

  /// Unsubscribe from [_camCountTopic] and clear the callback.
  void unsubscribeFromCamCount() {
    _camCountCallback = null;
    try {
      _client?.unsubscribe(_camCountTopic);
    } catch (_) {}
  }

  /// Whether a cam-count subscription is currently active.
  bool get isCamCountSubscribed => _camCountCallback != null;

  int? _parseCount(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void dispose() {
    _statusController.close();
  }
}
