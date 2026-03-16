# 05 — Data Layer (API, MQTT, Storage Services)

## Purpose
Migrate the data fetching, MQTT real-time updates, and local storage from JavaScript to Dart services. This replaces `DataContext.js`, `config/api.js`, `routeStorage.js`, and `busRouteMapping.js`.

## Source Files Being Replaced
- `contexts/DataContext.js` → `lib/providers/data_provider.dart` + `lib/services/mqtt_service.dart`
- `config/api.js` → `lib/config/api_config.dart` + `lib/services/api_service.dart`
- `config/env.js` → `lib/config/env.dart`
- `utils/routeStorage.js` → `lib/services/route_storage_service.dart`
- `utils/busRouteMapping.js` → `lib/services/bus_mapping_service.dart`
- `utils/defaultRoutes.js` → `lib/services/default_routes_service.dart`

---

## 1. Environment Config

### `lib/config/env.dart`

```dart
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
```

### `lib/config/api_config.dart`

```dart
import 'dart:io' show Platform;
import 'env.dart';

class ApiConfig {
  /// Base URL for HTTP API
  static String get baseUrl {
    if (Env.isTunnelMode) return Env.apiUrl;

    String host = Env.serverIp;
    // Android emulator needs 10.0.2.2 to reach host's localhost
    if (Platform.isAndroid && (host == 'localhost' || host == '127.0.0.1')) {
      host = '10.0.2.2';
    }
    return 'http://$host:${Env.apiPort}';
  }

  /// MQTT WebSocket URL
  static String get mqttWsUrl {
    if (Env.isTunnelMode) return 'ws://${Env.mqttBrokerHost}:${Env.mqttWebSocketPort}';

    String host = Env.mqttBrokerHost.isEmpty ? Env.serverIp : Env.mqttBrokerHost;
    if (Platform.isAndroid && (host == 'localhost' || host == '127.0.0.1')) {
      host = '10.0.2.2';
    }
    return 'ws://$host:${Env.mqttWebSocketPort}';
  }

  /// Headers for API requests
  static Map<String, String> get headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (Env.apiSecretKey.isNotEmpty) {
      h['X-API-Key'] = Env.apiSecretKey;
    }
    return h;
  }
}
```

---

## 2. API Service (replaces `axios` calls)

### `lib/services/api_service.dart`

```dart
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/bus.dart';
import '../models/route_model.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: ApiConfig.headers,
    ));
  }

  // ─── Buses ───────────────────────────────────────

  Future<List<Bus>> fetchBuses() async {
    try {
      final response = await _dio.get('/api/buses');
      if (response.data is List) {
        return (response.data as List).map((j) => Bus.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('[ApiService] Error fetching buses: $e');
      return [];
    }
  }

  Future<int?> fetchPassengerCount() async {
    try {
      final response = await _dio.get('/count');
      return response.data['passengers'] as int?;
    } catch (e) {
      return null;
    }
  }

  // ─── Routes ──────────────────────────────────────

  Future<List<BusRoute>> fetchRoutes() async {
    try {
      final response = await _dio.get('/api/routes');
      if (response.data is List) {
        final routes = <BusRoute>[];
        for (final r in response.data) {
          try {
            final stopsRes = await _dio.get('/api/routes/${r['id']}/stops');
            routes.add(BusRoute.fromJson({
              ...r as Map<String, dynamic>,
              'waypoints': stopsRes.data ?? [],
            }));
          } catch (e) {
            routes.add(BusRoute.fromJson({...r as Map<String, dynamic>, 'waypoints': []}));
          }
        }
        return routes;
      }
      return [];
    } catch (e) {
      print('[ApiService] Error fetching routes: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchRouteList() async {
    try {
      final response = await _dio.get('/api/routes/list');
      return List<Map<String, dynamic>>.from(response.data['routes'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<BusRoute?> fetchRoute(String routeId) async {
    try {
      final response = await _dio.get('/api/routes/$routeId');
      return BusRoute.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<bool> syncRoute(BusRoute route) async {
    try {
      final response = await _dio.post('/api/routes', data: route.toJson());
      return response.data?['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteRoute(String routeId) async {
    try {
      await _dio.delete('/api/routes/$routeId');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── Bus Management ──────────────────────────────

  Future<bool> createBus(String mac, String name) async {
    try {
      await _dio.post('/api/buses', data: {'mac_address': mac, 'bus_name': name});
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateBus(String mac, String name) async {
    try {
      await _dio.put('/api/buses/$mac', data: {'bus_name': name});
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteBus(String mac) async {
    try {
      await _dio.delete('/api/buses/$mac');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── Bus Route Mapping ───────────────────────────

  Future<Map<String, dynamic>?> fetchBusRouteMappings(int localVersion) async {
    try {
      final response = await _dio.get(
        '/api/bus-route-mapping',
        queryParameters: {'version': localVersion},
      );
      return response.data;
    } catch (e) {
      return null;
    }
  }

  // ─── Air Quality ─────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchHeatmapData({String timeRange = '1h'}) async {
    try {
      final response = await _dio.get('/api/pm/heatmap', queryParameters: {'range': timeRange});
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> sendFakeLocation(Map<String, dynamic> data) async {
    try {
      await _dio.post('/api/debug/location', data: data);
    } catch (e) {
      // Silent
    }
  }

  Future<void> deleteFakeLocation(String busId) async {
    try {
      await _dio.delete('/api/debug/location/$busId');
    } catch (e) {
      // Silent
    }
  }
}
```

---

## 3. MQTT Service (replaces `mqtt` npm package)

### `lib/services/mqtt_service.dart`

```dart
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import '../config/api_config.dart';

typedef MqttMessageCallback = void Function(String topic, Map<String, dynamic> data);

class MqttService {
  MqttBrowserClient? _client;
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
      // Extract host and port from ws://host:port
      final uri = Uri.parse(wsUrl);

      _client = MqttBrowserClient('ws://${uri.host}', 'sut_smart_bus_flutter_${DateTime.now().millisecondsSinceEpoch}')
        ..port = uri.port
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..resubscribeOnAutoReconnect = true
        ..logging(on: false)
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected;

      await _client!.connect();
    } catch (e) {
      print('[MqttService] Connection error: $e');
    } finally {
      _isConnecting = false;
    }
  }

  void _onConnected() {
    print('[MqttService] Connected to MQTT Broker');

    // Subscribe to all topics
    for (final topic in _topics) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
    }

    // Listen for messages
    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final payload = msg.payload as MqttPublishMessage;
        final payloadStr = MqttPublishPayload.bytesToStringAsString(payload.payload.message);

        try {
          final data = jsonDecode(payloadStr) as Map<String, dynamic>;
          onMessage?.call(msg.topic, data);
        } catch (e) {
          // Silent parse error
        }
      }
    });
  }

  void _onDisconnected() {
    print('[MqttService] Disconnected from MQTT Broker');
  }

  void disconnect() {
    _client?.disconnect();
  }
}
```

> **Note:** For native Android/iOS (non-web), use `MqttServerClient` instead of `MqttBrowserClient`. Create a factory method:
> ```dart
> import 'package:flutter/foundation.dart' show kIsWeb;
> // Use MqttBrowserClient on web, MqttServerClient on mobile
> ```

---

## 4. Data Provider (replaces DataContext.js)

### `lib/providers/data_provider.dart`

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import '../services/route_storage_service.dart';

class DataState {
  final List<Bus> buses;
  final List<BusRoute> routes;
  final bool loading;
  final String? error;

  DataState({
    this.buses = const [],
    this.routes = const [],
    this.loading = true,
    this.error,
  });

  DataState copyWith({
    List<Bus>? buses,
    List<BusRoute>? routes,
    bool? loading,
    String? error,
  }) {
    return DataState(
      buses: buses ?? this.buses,
      routes: routes ?? this.routes,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class DataNotifier extends StateNotifier<DataState> {
  final ApiService _api;
  final MqttService _mqtt;
  Timer? _pollingTimer;

  DataNotifier(this._api, this._mqtt) : super(DataState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      state = state.copyWith(loading: true);

      // 1. Fetch routes
      final routes = await _api.fetchRoutes();
      state = state.copyWith(routes: routes);

      // 2. Fetch buses
      await refreshBuses();

      // 3. Connect MQTT
      _mqtt.onMessage = _handleMqttMessage;
      await _mqtt.connect();

      // 4. Start polling fallback (every 10s)
      _pollingTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => refreshBuses(),
      );

      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refreshBuses() async {
    final apiBuses = await _api.fetchBuses();
    if (apiBuses.isEmpty) return;

    final merged = _mergeBuses(state.buses, apiBuses);
    state = state.copyWith(buses: merged);
  }

  /// Smart merge: preserves MQTT real-time data, handles name protection
  List<Bus> _mergeBuses(List<Bus> existing, List<Bus> incoming) {
    final merged = [...existing];

    for (final apiBus in incoming) {
      final idx = merged.indexWhere((b) => b.busMac == apiBus.busMac);

      if (idx >= 0) {
        final local = merged[idx];
        final localIsFresher = local.lastUpdated > apiBus.lastUpdated;

        // Name protection: keep the better name
        String finalName = apiBus.busName;
        if (local.busName.isNotEmpty &&
            !local.busName.startsWith('Bus-') &&
            local.busName != 'Bus') {
          if (apiBus.busName.isEmpty || apiBus.busName.startsWith('Bus-')) {
            finalName = local.busName;
          }
        }

        if (localIsFresher) {
          merged[idx] = local.copyWith(busName: finalName);
        } else {
          merged[idx] = apiBus.copyWith(
            busName: finalName,
            rssi: local.rssi,
            isOnline: local.isOnline,
            currentLat: apiBus.currentLat ?? local.currentLat,
            currentLon: apiBus.currentLon ?? local.currentLon,
            pm25: apiBus.pm25 ?? local.pm25,
            pm10: apiBus.pm10 ?? local.pm10,
            temp: apiBus.temp ?? local.temp,
            hum: apiBus.hum ?? local.hum,
          );
        }
      } else if (merged.length < 50) {
        merged.add(apiBus);
      }
    }
    return merged;
  }

  void _handleMqttMessage(String topic, Map<String, dynamic> data) {
    if (topic == 'sut/app/bus/location' || topic == 'sut/bus/gps') {
      _handleLocationUpdate(data);
    } else if (topic == 'sut/bus/gps/fast') {
      _handleFastGpsUpdate(data);
    } else if (topic.contains('/status')) {
      _handleStatusUpdate(topic, data);
    }
  }

  void _handleLocationUpdate(Map<String, dynamic> data) {
    final busMac = data['bus_mac'] as String?;
    if (busMac == null) return;

    final buses = [...state.buses];
    final idx = buses.indexWhere((b) => b.busMac == busMac);

    if (idx >= 0) {
      buses[idx] = buses[idx].copyWith(
        busName: data['bus_name'] as String? ?? buses[idx].busName,
        currentLat: (data['lat'] as num?)?.toDouble(),
        currentLon: (data['lon'] as num?)?.toDouble(),
        seatsAvailable: data['seats_available'] as int?,
        pm25: (data['pm2_5'] as num?)?.toDouble(),
        pm10: (data['pm10'] as num?)?.toDouble(),
        temp: (data['temp'] as num?)?.toDouble(),
        hum: (data['hum'] as num?)?.toDouble(),
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      );
    } else if (buses.length < 50) {
      buses.add(Bus(
        id: busMac,
        busMac: busMac,
        busName: data['bus_name'] as String? ?? 'Bus-${busMac.substring(busMac.length - 4)}',
        currentLat: (data['lat'] as num?)?.toDouble(),
        currentLon: (data['lon'] as num?)?.toDouble(),
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    state = state.copyWith(buses: buses);
  }

  void _handleFastGpsUpdate(Map<String, dynamic> data) {
    final busMac = data['bus_mac'] as String?;
    if (busMac == null || data['lat'] == null || data['lon'] == null) return;

    final buses = [...state.buses];
    final idx = buses.indexWhere((b) => b.busMac == busMac);
    if (idx >= 0) {
      buses[idx] = buses[idx].copyWith(
        currentLat: (data['lat'] as num).toDouble(),
        currentLon: (data['lon'] as num).toDouble(),
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      );
      state = state.copyWith(buses: buses);
    }
  }

  void _handleStatusUpdate(String topic, Map<String, dynamic> data) {
    final parts = topic.split('/');
    if (parts.length < 3) return;
    final busId = parts[2];

    if (data['rssi'] == null) return;

    final buses = [...state.buses];
    final idx = buses.indexWhere((b) => b.busMac == busId);
    if (idx >= 0) {
      buses[idx] = buses[idx].copyWith(
        rssi: data['rssi'] as int?,
        isOnline: true,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      );
      state = state.copyWith(buses: buses);
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _mqtt.disconnect();
    super.dispose();
  }
}

// ─── Riverpod Providers ────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
final mqttServiceProvider = Provider<MqttService>((ref) => MqttService());

final dataProvider = StateNotifierProvider<DataNotifier, DataState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final mqtt = ref.watch(mqttServiceProvider);
  return DataNotifier(api, mqtt);
});

// Convenience selectors
final busesProvider = Provider<List<Bus>>((ref) => ref.watch(dataProvider).buses);
final routesProvider = Provider<List<BusRoute>>((ref) => ref.watch(dataProvider).routes);
final dataLoadingProvider = Provider<bool>((ref) => ref.watch(dataProvider).loading);
```

---

## 5. Route Storage Service (replaces routeStorage.js)

### `lib/services/route_storage_service.dart`

```dart
import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/route_model.dart';

class RouteStorageService {
  static const _boxName = 'bus_routes';

  Future<Box> _openBox() async => Hive.openBox(_boxName);

  Future<void> saveRoute(BusRoute route) async {
    final box = await _openBox();
    await box.put(route.routeId, jsonEncode(route.toJson()));
  }

  Future<BusRoute?> loadRoute(String routeId) async {
    final box = await _openBox();
    final json = box.get(routeId);
    if (json == null) return null;
    return BusRoute.fromJson(jsonDecode(json));
  }

  Future<List<BusRoute>> getAllRoutes() async {
    final box = await _openBox();
    return box.values
        .map((json) => BusRoute.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> deleteRoute(String routeId) async {
    final box = await _openBox();
    await box.delete(routeId);
  }

  Future<void> clearAll() async {
    final box = await _openBox();
    await box.clear();
  }
}
```

---

## Verification Checklist

- [ ] `ApiService` can fetch `/api/buses` and deserialize into `List<Bus>`
- [ ] `ApiService` can fetch `/api/routes` with stops and deserialize into `List<BusRoute>`
- [ ] `MqttService` connects to the WebSocket broker and receives messages
- [ ] `DataNotifier` merges API buses with MQTT updates correctly
- [ ] `DataNotifier` implements name protection logic
- [ ] `RouteStorageService` can save and load routes from Hive
- [ ] Polling fallback fetches buses every 10 seconds
- [ ] MQTT topics match: `sut/app/bus/location`, `sut/bus/gps/fast`, `sut/bus/gps`, `sut/bus/+/status`
