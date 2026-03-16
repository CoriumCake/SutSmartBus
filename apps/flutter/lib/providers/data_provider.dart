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
        busName: data['bus_name'] as String? ?? 'Bus-${busMac.length >= 4 ? busMac.substring(busMac.length - 4) : ''}',
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
