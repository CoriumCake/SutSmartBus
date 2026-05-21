import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';

const int _maxBusPassengerCount = 40;
const int _totalBusCapacity = 40;
const double _defaultBusParkingLat = 14.878001729445229;
const double _defaultBusParkingLon = 102.02142930035654;
const double _parkingResetRadiusMeters = 35;
const int _authoritativePassengerCountFreshMs = 120000;

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
  final dLon = (lon2 - lon1) * 3.141592653589793 / 180.0;
  final a = (sin(dLat / 2) * sin(dLat / 2)) +
      cos(lat1 * 3.141592653589793 / 180.0) *
          cos(lat2 * 3.141592653589793 / 180.0) *
          (sin(dLon / 2) * sin(dLon / 2));
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusMeters * c;
}

bool _isAtDefaultParking(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  return _distanceMeters(
        lat,
        lon,
        _defaultBusParkingLat,
        _defaultBusParkingLon,
      ) <=
      _parkingResetRadiusMeters;
}

int _normalizePassengerCount(
  int count, {
  double? lat,
  double? lon,
  bool resetAtParking = true,
}) {
  if (resetAtParking && _isAtDefaultParking(lat, lon)) {
    return 0;
  }
  return count.clamp(0, _maxBusPassengerCount).toInt();
}

int? _normalizeRssi(dynamic value) {
  return value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
}

class DataState {
  final List<Bus> buses;
  final List<BusRoute> routes;
  final bool loading;
  final String? error;
  final MqttConnectionState mqttStatus;

  DataState({
    this.buses = const [],
    this.routes = const [],
    this.loading = true,
    this.error,
    this.mqttStatus = MqttConnectionState.disconnected,
  });

  DataState copyWith({
    List<Bus>? buses,
    List<BusRoute>? routes,
    bool? loading,
    String? error,
    MqttConnectionState? mqttStatus,
  }) {
    return DataState(
      buses: buses ?? this.buses,
      routes: routes ?? this.routes,
      loading: loading ?? this.loading,
      error: error,
      mqttStatus: mqttStatus ?? this.mqttStatus,
    );
  }
}

class DataNotifier extends StateNotifier<DataState> {
  final ApiService _api;
  final MqttService _mqtt;
  Timer? _pollingTimer;
  Timer? _presenceTimer;
  Map<String, String> _busRouteMappings = {};
  final Map<String, Map<String, bool>> _componentOnlineByBus = {};
  final Map<String, int> _lastAuthoritativePassengerCountAt = {};

  DataNotifier(this._api, this._mqtt) : super(DataState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      state = state.copyWith(loading: true);

      // 1. Fetch routes
      var apiRoutes = await _api.fetchRoutes();
      _busRouteMappings = await _loadBusRouteMappings();
      final bundledRoute = await _loadBundledRoute();

      final Map<String, BusRoute> routeMap = {};
      for (var r in apiRoutes) {
        routeMap[r.routeId] = r;
      }
      if (bundledRoute != null) {
        routeMap[bundledRoute.routeId] = bundledRoute;
      }

      var routes = routeMap.values.toList();

      if (routes.isEmpty) {
        // Local fallback for offline testing (SUT Green Route)
        routes = [
          BusRoute(
            routeId: 'local-01',
            routeName: 'SUT Shuttle (Local)',
            routeColor: '#2563EB',
            waypoints: [
              Waypoint(
                  latitude: 14.8816,
                  longitude: 102.0207,
                  isStop: true,
                  stopName: 'Main Gate'),
              Waypoint(
                  latitude: 14.8780,
                  longitude: 102.0180,
                  isStop: true,
                  stopName: 'Library'),
              Waypoint(
                  latitude: 14.8720,
                  longitude: 102.0150,
                  isStop: true,
                  stopName: 'Dormitory'),
            ],
          )
        ];
      }
      state = state.copyWith(routes: routes);

      // 2. Fetch buses
      await refreshBuses();

      // 3. Connect MQTT
      _mqtt.onMessage = handleMqttMessage;
      _mqtt.statusStream.listen((status) {
        state = state.copyWith(mqttStatus: status);
      });
      await _mqtt.connect();

      // 4. Start polling fallback (every 10s)
      _pollingTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => refreshBuses(),
      );

      // 5. Force lightweight UI refreshes so offline/online status
      // can age out even when no new MQTT or API payload arrives.
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => state = state.copyWith(),
      );

      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refreshBuses() async {
    _busRouteMappings = await _loadBusRouteMappings();
    final apiBuses = (await _api.fetchBuses()).map(_applyRouteMapping).toList();
    // Allow empty list to update state if necessary
    final merged = _mergeBuses(state.buses, apiBuses);
    state = state.copyWith(buses: merged);
  }

  Future<Map<String, String>> _loadBusRouteMappings() async {
    final singleRouteId = _singleRouteId;
    if (singleRouteId != null) {
      return {};
    }

    final remote = await _api.fetchBusRouteMappings(0);
    final remoteMappings = <String, String>{};

    final mappings = remote?['mappings'];
    if (mappings is List) {
      for (final entry in mappings) {
        if (entry is! Map) continue;
        final mappedBusId = entry['bus_id']?.toString();
        final busMac = entry['bus_mac']?.toString();
        final routeId = entry['route_id']?.toString();
        if (routeId == null || routeId.isEmpty) {
          continue;
        }
        if (mappedBusId != null && mappedBusId.isNotEmpty) {
          remoteMappings[mappedBusId] = routeId;
        }
        if (busMac != null && busMac.isNotEmpty) {
          remoteMappings[busMac] = routeId;
        }
      }
    }

    return remoteMappings;
  }

  Future<BusRoute?> _loadBundledRoute() async {
    try {
      final content = await rootBundle.loadString('assets/routes/route.json');
      final json = jsonDecode(content) as Map<String, dynamic>;
      return BusRoute.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  String? get _singleRouteId {
    final routes = state.routes;
    if (routes.length != 1) {
      return null;
    }

    final routeId = routes.first.routeId.trim();
    return routeId.isEmpty ? null : routeId;
  }

  Bus _applyRouteMapping(Bus bus) {
    final singleRouteId = _singleRouteId;
    if (singleRouteId != null) {
      return bus.copyWith(routeId: singleRouteId);
    }

    if (bus.routeId != null && bus.routeId!.isNotEmpty) {
      return bus;
    }

    final mappedRouteId = (bus.busId != null
            ? _busRouteMappings[bus.busId!]
            : null) ??
        _busRouteMappings[bus.busMac] ??
        (bus.macAddress != null ? _busRouteMappings[bus.macAddress!] : null);

    if (mappedRouteId == null || mappedRouteId.isEmpty) {
      return bus;
    }

    return bus.copyWith(routeId: mappedRouteId);
  }

  bool _isInvalidHardwareBusMac(String? busMac) {
    if (busMac == null) return true;
    final normalized = busMac.trim().toUpperCase();
    return normalized.isEmpty || normalized == '00:00:00:00:00:00';
  }

  bool _isInvalidBusId(String? busId) {
    return busId == null || busId.trim().isEmpty;
  }

  int _findBusIndexByIdentity(
    List<Bus> buses, {
    String? busId,
    String? busMac,
    String? busName,
  }) {
    final normalizedBusId = busId?.trim();
    if (!_isInvalidBusId(normalizedBusId)) {
      final idx = buses.indexWhere((b) => b.busId == normalizedBusId);
      if (idx >= 0) return idx;
      final fallbackIdx = buses.indexWhere((b) => b.id == normalizedBusId);
      if (fallbackIdx >= 0) return fallbackIdx;
    }

    if (!_isInvalidHardwareBusMac(busMac)) {
      final idx = buses.indexWhere((b) => b.busMac == busMac);
      if (idx >= 0) return idx;
    }

    final normalizedName = busName?.trim();
    if (normalizedName != null && normalizedName.isNotEmpty) {
      return buses.indexWhere((b) => b.busName.trim() == normalizedName);
    }

    return -1;
  }

  String? _presenceKeyForBus({
    Bus? bus,
    String? busId,
    String? busMac,
    String? busName,
    String? topicBusId,
  }) {
    final normalizedBusId = bus?.busId?.trim();
    if (normalizedBusId != null && normalizedBusId.isNotEmpty) {
      return normalizedBusId;
    }
    final payloadBusId = busId?.trim();
    if (payloadBusId != null && payloadBusId.isNotEmpty) {
      return payloadBusId;
    }
    final busModelName = bus?.busName.trim();
    if (busModelName != null && busModelName.isNotEmpty) {
      return busModelName;
    }
    final normalizedName = busName?.trim();
    if (normalizedName != null && normalizedName.isNotEmpty) {
      return normalizedName;
    }
    if (bus != null) return bus.busMac;
    if (!_isInvalidHardwareBusMac(busMac)) return busMac;
    final normalizedTopicId = topicBusId?.trim();
    if (normalizedTopicId != null && normalizedTopicId.isNotEmpty) {
      return normalizedTopicId;
    }
    return null;
  }

  bool _recordComponentStatus(
    String busKey,
    String component,
    bool isOnline,
  ) {
    final componentStates =
        _componentOnlineByBus.putIfAbsent(busKey, () => <String, bool>{});
    componentStates[component] = isOnline;
    return !componentStates.values.any((status) => status == false);
  }

  bool _isAuthoritativePassengerPayload(Map<String, dynamic> data) {
    final source =
        (data['count_source'] ?? data['source'] ?? '').toString().toLowerCase();
    return source == 'door' || data['dir'] != null;
  }

  void _markAuthoritativePassengerCount({
    Bus? bus,
    String? busId,
    String? busMac,
    String? busName,
  }) {
    final key = _presenceKeyForBus(
      bus: bus,
      busId: busId,
      busMac: busMac,
      busName: busName,
    );
    if (key == null) return;
    _lastAuthoritativePassengerCountAt[key] =
        DateTime.now().millisecondsSinceEpoch;
  }

  bool _shouldIgnoreNonAuthoritativeZero({
    required int? incomingCount,
    required Bus? existingBus,
    required bool hasPayloadLocation,
    required bool isAuthoritative,
    String? busId,
    String? busMac,
    String? busName,
  }) {
    if (incomingCount != 0 ||
        existingBus?.personCount == null ||
        existingBus!.personCount! <= 0 ||
        hasPayloadLocation ||
        isAuthoritative) {
      return false;
    }

    final key = _presenceKeyForBus(
      bus: existingBus,
      busId: busId,
      busMac: busMac,
      busName: busName,
    );
    final lastAuthoritativeAt =
        key == null ? null : _lastAuthoritativePassengerCountAt[key];
    if (lastAuthoritativeAt == null) {
      return true;
    }

    return DateTime.now().millisecondsSinceEpoch - lastAuthoritativeAt <=
        _authoritativePassengerCountFreshMs;
  }

  /// Smart merge: preserves MQTT real-time data, handles name protection
  List<Bus> _mergeBuses(List<Bus> existing, List<Bus> incoming) {
    final merged = [...existing];

    for (final apiBus in incoming) {
      final idx = _findBusIndexByIdentity(
        merged,
        busId: apiBus.busId,
        busMac: apiBus.busMac,
        busName: apiBus.busName,
      );

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
          merged[idx] = _applyRouteMapping(local.copyWith(
            busId: apiBus.busId ?? local.busId,
            busName: finalName,
          ));
        } else {
          final preserveLocalPassengerCount = _shouldIgnoreNonAuthoritativeZero(
            incomingCount: apiBus.personCount,
            existingBus: local,
            hasPayloadLocation: false,
            isAuthoritative: false,
            busId: apiBus.busId,
            busMac: apiBus.busMac,
            busName: apiBus.busName,
          );
          merged[idx] = _applyRouteMapping(apiBus.copyWith(
            busName: finalName,
            rssi: apiBus.rssi ?? local.rssi,
            isOnline: local.isOnline,
            currentLat: apiBus.currentLat ?? local.currentLat,
            currentLon: apiBus.currentLon ?? local.currentLon,
            pm25: apiBus.pm25 ?? local.pm25,
            pm10: apiBus.pm10 ?? local.pm10,
            temp: apiBus.temp ?? local.temp,
            hum: apiBus.hum ?? local.hum,
            personCount: preserveLocalPassengerCount
                ? local.personCount
                : apiBus.personCount,
            seatsAvailable: preserveLocalPassengerCount
                ? local.seatsAvailable
                : apiBus.seatsAvailable,
          ));
        }
      } else if (merged.length < 50) {
        merged.add(_applyRouteMapping(apiBus));
      }
    }
    return merged;
  }

  void handleMqttMessage(String topic, Map<String, dynamic> data) {
    if (topic == 'sut/app/bus/location' || topic == 'sut/bus/gps') {
      _handleLocationUpdate(data);
    } else if (topic == 'sut/bus/gps/fast') {
      _handleFastGpsUpdate(data);
    } else if (topic.contains('/status')) {
      _handleStatusUpdate(topic, data);
    } else if (topic == 'bus/door/count') {
      _handleDoorCountUpdate(data);
    }
  }

  void _handleDoorCountUpdate(Map<String, dynamic> data) {
    final busId = (data['bus_id'] as String?)?.trim();
    // If hardware doesn't send bus_mac, we default to the mock MAC
    // In a multi-bus system, hardware should be updated to send its MAC
    final busMac = data['bus_mac'] as String? ?? 'ESP32-CAM-01';
    final busName = (data['bus_name'] as String?)?.trim();
    final count = data['count'] as int?;
    if (count == null) return;
    final payloadLat = (data['lat'] as num?)?.toDouble();
    final payloadLon = (data['lon'] as num?)?.toDouble();
    final hasPayloadLocation = payloadLat != null && payloadLon != null;

    final buses = [...state.buses];
    int idx = _findBusIndexByIdentity(
      buses,
      busId: busId,
      busMac: busMac,
      busName: busName,
    );

    if (idx >= 0) {
      final normalizedCount = _normalizePassengerCount(
        count,
        lat: payloadLat,
        lon: payloadLon,
        resetAtParking: hasPayloadLocation,
      );
      buses[idx] = _applyRouteMapping(buses[idx].copyWith(
        busId: busId ?? buses[idx].busId,
        busName: (busName != null && busName.isNotEmpty)
            ? busName
            : buses[idx].busName,
        currentLat: payloadLat ?? buses[idx].currentLat,
        currentLon: payloadLon ?? buses[idx].currentLon,
        isOnline: true,
        personCount: normalizedCount,
        seatsAvailable:
            (_totalBusCapacity - normalizedCount).clamp(0, _totalBusCapacity),
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ));
      _markAuthoritativePassengerCount(bus: buses[idx]);
    } else if (buses.length < 50) {
      final normalizedCount = _normalizePassengerCount(
        count,
        lat: payloadLat,
        lon: payloadLon,
        resetAtParking: hasPayloadLocation,
      );
      final effectiveBusId = !_isInvalidBusId(busId) ? busId!.trim() : busMac;
      final nextBus = _applyRouteMapping(Bus(
        id: effectiveBusId,
        busId: !_isInvalidBusId(busId) ? busId!.trim() : null,
        busMac: busMac,
        busName: busName ??
            'Bus-${effectiveBusId.length >= 4 ? effectiveBusId.substring(effectiveBusId.length - 4) : effectiveBusId}',
        currentLat: payloadLat,
        currentLon: payloadLon,
        isOnline: true,
        personCount: normalizedCount,
        seatsAvailable:
            (_totalBusCapacity - normalizedCount).clamp(0, _totalBusCapacity),
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ));
      buses.add(nextBus);
      _markAuthoritativePassengerCount(bus: nextBus);
    }
    state = state.copyWith(buses: buses);
  }

  /// Manually inject or update a bus in the local state (used by simulation)
  void updateBusLocally(Bus bus) {
    final buses = [...state.buses];
    final idx = buses.indexWhere((b) => b.id == bus.id);

    if (idx >= 0) {
      buses[idx] = bus;
    } else {
      buses.add(bus);
    }
    state = state.copyWith(buses: buses);
  }

  void removeBusLocally(String id) {
    final buses = [...state.buses];
    buses.removeWhere((b) => b.id == id);
    state = state.copyWith(buses: buses);
  }

  void _handleLocationUpdate(Map<String, dynamic> data) {
    final busId = (data['bus_id'] as String?)?.trim();
    final busMac = data['bus_mac'] as String?;
    final busName = (data['bus_name'] as String?)?.trim();
    if (_isInvalidBusId(busId) &&
        _isInvalidHardwareBusMac(busMac) &&
        (busName == null || busName.isEmpty)) {
      return;
    }
    final payloadLat = (data['lat'] as num?)?.toDouble();
    final payloadLon = (data['lon'] as num?)?.toDouble();
    final hasPayloadLocation = payloadLat != null && payloadLon != null;
    final isAuthoritativePassengerPayload =
        _isAuthoritativePassengerPayload(data);

    final buses = [...state.buses];
    final idx = _findBusIndexByIdentity(
      buses,
      busId: busId,
      busMac: busMac,
      busName: busName,
    );

    if (idx >= 0) {
      final nextLat = payloadLat ?? buses[idx].currentLat;
      final nextLon = payloadLon ?? buses[idx].currentLon;
      final rawPersonCount =
          data['person_count'] as int? ?? buses[idx].personCount;
      final ignoreZero = _shouldIgnoreNonAuthoritativeZero(
        incomingCount: rawPersonCount,
        existingBus: buses[idx],
        hasPayloadLocation: hasPayloadLocation,
        isAuthoritative: isAuthoritativePassengerPayload,
        busId: busId,
        busMac: busMac,
        busName: busName,
      );
      final normalizedPersonCount = rawPersonCount == null || ignoreZero
          ? null
          : _normalizePassengerCount(rawPersonCount,
              lat: payloadLat,
              lon: payloadLon,
              resetAtParking: hasPayloadLocation);
      buses[idx] = _applyRouteMapping(buses[idx].copyWith(
        busId: busId ?? buses[idx].busId,
        busName: busName?.isNotEmpty == true ? busName! : buses[idx].busName,
        currentLat: nextLat,
        currentLon: nextLon,
        isOnline: true,
        seatsAvailable: normalizedPersonCount != null
            ? (_totalBusCapacity - normalizedPersonCount)
                .clamp(0, _totalBusCapacity)
            : data['seats_available'] as int? ?? buses[idx].seatsAvailable,
        pm25: (data['pm2_5'] as num?)?.toDouble() ?? buses[idx].pm25,
        pm10: (data['pm10'] as num?)?.toDouble() ?? buses[idx].pm10,
        temp: (data['temp'] as num?)?.toDouble() ?? buses[idx].temp,
        hum: (data['hum'] as num?)?.toDouble() ?? buses[idx].hum,
        rssi: _normalizeRssi(data['rssi']) ?? buses[idx].rssi,
        personCount: normalizedPersonCount ?? buses[idx].personCount,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ));
      if (normalizedPersonCount != null && isAuthoritativePassengerPayload) {
        _markAuthoritativePassengerCount(bus: buses[idx]);
      }
    } else if (buses.length < 50) {
      final effectiveBusMac = _isInvalidHardwareBusMac(busMac)
          ? (busName ?? busId ?? 'ESP32-CAM-01')
          : busMac!;
      final effectiveBusId = !_isInvalidBusId(busId) ? busId!.trim() : null;
      final nextLat = payloadLat;
      final nextLon = payloadLon;
      final rawNewPersonCount = data['person_count'] as int?;
      final ignoreNewZero = rawNewPersonCount == 0 &&
          !hasPayloadLocation &&
          !isAuthoritativePassengerPayload;
      final normalizedPersonCount = rawNewPersonCount == null || ignoreNewZero
          ? null
          : _normalizePassengerCount(
              rawNewPersonCount,
              lat: payloadLat,
              lon: payloadLon,
              resetAtParking: hasPayloadLocation,
            );
      final nextBus = _applyRouteMapping(Bus(
        id: effectiveBusId ?? effectiveBusMac,
        busId: effectiveBusId,
        busMac: effectiveBusMac,
        busName: busName ??
            'Bus-${(effectiveBusId ?? effectiveBusMac).length >= 4 ? (effectiveBusId ?? effectiveBusMac).substring((effectiveBusId ?? effectiveBusMac).length - 4) : ''}',
        currentLat: nextLat,
        currentLon: nextLon,
        pm25: (data['pm2_5'] as num?)?.toDouble(),
        pm10: (data['pm10'] as num?)?.toDouble(),
        temp: (data['temp'] as num?)?.toDouble(),
        hum: (data['hum'] as num?)?.toDouble(),
        rssi: _normalizeRssi(data['rssi']),
        isOnline: true,
        personCount: normalizedPersonCount,
        seatsAvailable: normalizedPersonCount != null
            ? (_totalBusCapacity - normalizedPersonCount)
                .clamp(0, _totalBusCapacity)
            : data['seats_available'] as int?,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ));
      buses.add(nextBus);
      if (normalizedPersonCount != null && isAuthoritativePassengerPayload) {
        _markAuthoritativePassengerCount(bus: nextBus);
      }
    }
    state = state.copyWith(buses: buses);
  }

  void _handleFastGpsUpdate(Map<String, dynamic> data) {
    final busId = (data['bus_id'] as String?)?.trim();
    final busMac = data['bus_mac'] as String?;
    final busName = (data['bus_name'] as String?)?.trim();
    if ((_isInvalidBusId(busId) &&
            _isInvalidHardwareBusMac(busMac) &&
            (busName == null || busName.isEmpty)) ||
        data['lat'] == null ||
        data['lon'] == null) {
      return;
    }

    final buses = [...state.buses];
    final idx = _findBusIndexByIdentity(
      buses,
      busId: busId,
      busMac: busMac,
      busName: busName,
    );
    if (idx >= 0) {
      buses[idx] = _applyRouteMapping(buses[idx].copyWith(
        busId: busId ?? buses[idx].busId,
        currentLat: (data['lat'] as num).toDouble(),
        currentLon: (data['lon'] as num).toDouble(),
        isOnline: true,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ));
    } else if (buses.length < 50) {
      final effectiveBusMac = _isInvalidHardwareBusMac(busMac)
          ? (busName ?? busId ?? 'ESP32-CAM-01')
          : busMac!;
      final effectiveBusId = !_isInvalidBusId(busId) ? busId!.trim() : null;
      buses.add(_applyRouteMapping(Bus(
        id: effectiveBusId ?? effectiveBusMac,
        busId: effectiveBusId,
        busMac: effectiveBusMac,
        busName: busName ??
            'Bus-${(effectiveBusId ?? effectiveBusMac).length >= 4 ? (effectiveBusId ?? effectiveBusMac).substring((effectiveBusId ?? effectiveBusMac).length - 4) : ''}',
        currentLat: (data['lat'] as num).toDouble(),
        currentLon: (data['lon'] as num).toDouble(),
        isOnline: true,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      )));
    }
    state = state.copyWith(buses: buses);
  }

  void _handleStatusUpdate(String topic, Map<String, dynamic> data) {
    final parts = topic.split('/');
    if (parts.length < 4) return; // sut/bus/<MAC>/status
    final topicIdentity = parts[2];
    final payloadBusId = (data['bus_id'] as String?)?.trim();
    final statusBusMac = data['bus_mac']?.toString();
    final statusBusName = (data['bus_name'] as String?)?.trim();
    final componentName = data['component']?.toString().trim().toLowerCase();
    final component = (componentName != null && componentName.isNotEmpty)
        ? componentName
        : 'device';
    final statusIsOnline = data['is_online'] != false;

    final buses = [...state.buses];
    final idx = _findBusIndexByIdentity(
      buses,
      busId: payloadBusId,
      busMac: statusBusMac ?? topicIdentity,
      busName: statusBusName,
    );
    final presenceKey = _presenceKeyForBus(
      bus: idx >= 0 ? buses[idx] : null,
      busId: payloadBusId,
      busMac: statusBusMac ?? topicIdentity,
      busName: statusBusName,
      topicBusId: topicIdentity,
    );
    final combinedOnline = presenceKey == null
        ? statusIsOnline
        : _recordComponentStatus(presenceKey, component, statusIsOnline);

    int? count = data['count'] as int?;
    final rawPersonCount = data['person_count'] as int? ?? count;
    final payloadLat = (data['lat'] as num?)?.toDouble();
    final payloadLon = (data['lon'] as num?)?.toDouble();
    final hasPayloadLocation = payloadLat != null && payloadLon != null;
    final isAuthoritativePassengerPayload =
        _isAuthoritativePassengerPayload(data);

    if (idx >= 0) {
      final ignoreZero = _shouldIgnoreNonAuthoritativeZero(
        incomingCount: rawPersonCount,
        existingBus: buses[idx],
        hasPayloadLocation: hasPayloadLocation,
        isAuthoritative: isAuthoritativePassengerPayload,
        busId: payloadBusId,
        busMac: statusBusMac ?? topicIdentity,
        busName: statusBusName,
      );
      final normalizedPersonCount = rawPersonCount == null || ignoreZero
          ? null
          : _normalizePassengerCount(
              rawPersonCount,
              lat: payloadLat,
              lon: payloadLon,
              resetAtParking: hasPayloadLocation,
            );
      final seatsAvailable = normalizedPersonCount != null
          ? (_totalBusCapacity - normalizedPersonCount)
              .clamp(0, _totalBusCapacity)
          : null;
      buses[idx] = _applyRouteMapping(buses[idx].copyWith(
        busId: payloadBusId ?? buses[idx].busId,
        busName: statusBusName?.isNotEmpty == true
            ? statusBusName!
            : buses[idx].busName,
        currentLat: payloadLat ?? buses[idx].currentLat,
        currentLon: payloadLon ?? buses[idx].currentLon,
        rssi: _normalizeRssi(data['rssi']),
        isOnline: combinedOnline,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
        personCount: normalizedPersonCount ?? buses[idx].personCount,
        seatsAvailable: seatsAvailable ?? buses[idx].seatsAvailable,
      ));
      if (normalizedPersonCount != null && isAuthoritativePassengerPayload) {
        _markAuthoritativePassengerCount(bus: buses[idx]);
      }
    } else if (buses.length < 50) {
      final ignoreNewZero = rawPersonCount == 0 &&
          !hasPayloadLocation &&
          !isAuthoritativePassengerPayload;
      final normalizedPersonCount = rawPersonCount == null || ignoreNewZero
          ? null
          : _normalizePassengerCount(
              rawPersonCount,
              lat: payloadLat,
              lon: payloadLon,
              resetAtParking: hasPayloadLocation,
            );
      final seatsAvailable = normalizedPersonCount != null
          ? (_totalBusCapacity - normalizedPersonCount)
              .clamp(0, _totalBusCapacity)
          : null;
      final effectiveBusId =
          !_isInvalidBusId(payloadBusId) ? payloadBusId!.trim() : null;
      final nextBus = _applyRouteMapping(Bus(
        id: effectiveBusId ?? topicIdentity,
        busId: effectiveBusId,
        busMac: statusBusMac ?? topicIdentity,
        busName: statusBusName ??
            'Bus-${(effectiveBusId ?? topicIdentity).length >= 4 ? (effectiveBusId ?? topicIdentity).substring((effectiveBusId ?? topicIdentity).length - 4) : (effectiveBusId ?? topicIdentity)}',
        currentLat: payloadLat,
        currentLon: payloadLon,
        rssi: _normalizeRssi(data['rssi']),
        isOnline: combinedOnline,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
        personCount: normalizedPersonCount,
        seatsAvailable: seatsAvailable,
      ));
      buses.add(nextBus);
      if (normalizedPersonCount != null && isAuthoritativePassengerPayload) {
        _markAuthoritativePassengerCount(bus: nextBus);
      }
    }
    state = state.copyWith(buses: buses);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _presenceTimer?.cancel();
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
final busesProvider = Provider<List<Bus>>(
    (ref) => ref.watch(dataProvider.select((s) => s.buses)));
final routesProvider = Provider<List<BusRoute>>(
    (ref) => ref.watch(dataProvider.select((s) => s.routes)));
final dataLoadingProvider =
    Provider<bool>((ref) => ref.watch(dataProvider.select((s) => s.loading)));
final mqttStatusProvider = Provider<MqttConnectionState>(
    (ref) => ref.watch(dataProvider.select((s) => s.mqttStatus)));
