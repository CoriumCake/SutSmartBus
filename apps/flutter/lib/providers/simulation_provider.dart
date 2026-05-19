import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bus.dart';
import '../models/route_model.dart';
import '../services/api_service.dart';
import '../utils/map_utils.dart';
import 'data_provider.dart';

class SimulationState {
  final bool isSimulating;
  final String? simulatingBusId;
  final bool loopRoutes;
  final String? currentRouteId;
  final String? currentRouteName;
  final int currentRouteIndex;
  final int totalRoutes;
  final int currentWaypointIndex;
  final int totalWaypoints;
  final int completedLoops;
  final double speedMps;
  final String status;
  final bool hasDebugBus;

  const SimulationState({
    this.isSimulating = false,
    this.simulatingBusId,
    this.loopRoutes = true,
    this.currentRouteId,
    this.currentRouteName,
    this.currentRouteIndex = 0,
    this.totalRoutes = 0,
    this.currentWaypointIndex = 0,
    this.totalWaypoints = 0,
    this.completedLoops = 0,
    this.speedMps = 10.0,
    this.status = 'Idle',
    this.hasDebugBus = false,
  });

  SimulationState copyWith({
    bool? isSimulating,
    String? simulatingBusId,
    bool? loopRoutes,
    String? currentRouteId,
    String? currentRouteName,
    int? currentRouteIndex,
    int? totalRoutes,
    int? currentWaypointIndex,
    int? totalWaypoints,
    int? completedLoops,
    double? speedMps,
    String? status,
    bool? hasDebugBus,
    bool clearRoute = false,
  }) {
    return SimulationState(
      isSimulating: isSimulating ?? this.isSimulating,
      simulatingBusId: simulatingBusId ?? this.simulatingBusId,
      loopRoutes: loopRoutes ?? this.loopRoutes,
      currentRouteId: clearRoute ? null : (currentRouteId ?? this.currentRouteId),
      currentRouteName:
          clearRoute ? null : (currentRouteName ?? this.currentRouteName),
      currentRouteIndex: currentRouteIndex ?? this.currentRouteIndex,
      totalRoutes: totalRoutes ?? this.totalRoutes,
      currentWaypointIndex: currentWaypointIndex ?? this.currentWaypointIndex,
      totalWaypoints: totalWaypoints ?? this.totalWaypoints,
      completedLoops: completedLoops ?? this.completedLoops,
      speedMps: speedMps ?? this.speedMps,
      status: status ?? this.status,
      hasDebugBus: hasDebugBus ?? this.hasDebugBus,
    );
  }
}

class SimulationNotifier extends StateNotifier<SimulationState> {
  static const _debugBusMac = 'DEBUG-MAC-01';
  static const _tick = Duration(seconds: 2);

  final ApiService _api;
  final Ref _ref;

  Timer? _simTimer;
  final Random _random = Random();

  int _personCount = 0;
  List<BusRoute> _routeQueue = const [];
  int _routeIndex = 0;
  int _waypointIndex = 0;
  double _distanceIntoSegmentMeters = 0;
  double _currentLat = 14.8816;
  double _currentLon = 102.0207;

  SimulationNotifier(this._api, this._ref) : super(const SimulationState());

  void setPersonCount(int count) {
    _personCount = count.clamp(0, Bus.maxPassengerCount).toInt();
  }

  void setLoopRoutes(bool value) {
    state = state.copyWith(loopRoutes: value);
  }

  void setSpeedMps(double speedMps) {
    final normalized = speedMps.clamp(2.0, 20.0);
    state = state.copyWith(speedMps: normalized);
  }

  Future<void> toggleSimulation(
    bool value, {
    double? lat,
    double? lon,
    bool? loopRoutes,
    double? speedMps,
  }) async {
    if (value) {
      if (lat != null && lon != null) {
        _currentLat = lat;
        _currentLon = lon;
      }
      await _startSimulation(
        loopRoutes: loopRoutes ?? state.loopRoutes,
        speedMps: speedMps ?? state.speedMps,
      );
    } else {
      await _stopSimulation(removeBus: true, status: 'Simulation stopped');
    }
  }

  Future<void> clearDebugBus() async {
    await _stopSimulation(removeBus: true, status: 'Debug bus cleared');
  }

  Future<void> _startSimulation({
    required bool loopRoutes,
    required double speedMps,
  }) async {
    final routes = _ref
        .read(routesProvider)
        .where((route) => route.waypoints.length >= 2)
        .toList();

    if (routes.isEmpty) {
      state = state.copyWith(
        isSimulating: false,
        hasDebugBus: false,
        status: 'No routes available for simulation',
        totalRoutes: 0,
        currentRouteIndex: 0,
        currentWaypointIndex: 0,
        totalWaypoints: 0,
        clearRoute: true,
      );
      return;
    }

    _simTimer?.cancel();
    _routeQueue = routes;
    _routeIndex = 0;
    _waypointIndex = 0;
    _distanceIntoSegmentMeters = 0;
    _currentLat = routes.first.waypoints.first.latitude;
    _currentLon = routes.first.waypoints.first.longitude;

    state = state.copyWith(
      isSimulating: true,
      simulatingBusId: _debugBusMac,
      loopRoutes: loopRoutes,
      speedMps: speedMps.clamp(2.0, 20.0),
      hasDebugBus: true,
      completedLoops: 0,
      totalRoutes: routes.length,
      status: 'Driving route 1 of ${routes.length}',
    );
    _syncStateForCurrentRoute();

    await _publishCurrentBus();

    _simTimer = Timer.periodic(_tick, (_) async {
      await _advanceSimulation();
    });
  }

  Future<void> _advanceSimulation() async {
    if (_routeQueue.isEmpty || !state.isSimulating) {
      return;
    }

    var remainingStepMeters = state.speedMps * _tick.inMilliseconds / 1000;

    while (remainingStepMeters > 0 && state.isSimulating) {
      final route = _routeQueue[_routeIndex];
      final waypoints = route.waypoints;

      if (_waypointIndex >= waypoints.length - 1) {
        final advanced = _moveToNextRouteOrComplete();
        if (!advanced) {
          break;
        }
        continue;
      }

      final start = waypoints[_waypointIndex];
      final end = waypoints[_waypointIndex + 1];
      final segmentDistance = getDistanceFromLatLonInM(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );

      if (segmentDistance <= 0) {
        _waypointIndex++;
        _distanceIntoSegmentMeters = 0;
        _currentLat = end.latitude;
        _currentLon = end.longitude;
        _syncStateForCurrentRoute();
        continue;
      }

      final segmentRemaining = segmentDistance - _distanceIntoSegmentMeters;

      if (remainingStepMeters < segmentRemaining) {
        _distanceIntoSegmentMeters += remainingStepMeters;
        final t = _distanceIntoSegmentMeters / segmentDistance;
        _currentLat = _lerp(start.latitude, end.latitude, t);
        _currentLon = _lerp(start.longitude, end.longitude, t);
        remainingStepMeters = 0;
      } else {
        remainingStepMeters -= segmentRemaining;
        _waypointIndex++;
        _distanceIntoSegmentMeters = 0;
        _currentLat = end.latitude;
        _currentLon = end.longitude;
        _syncStateForCurrentRoute();

        if (_waypointIndex >= waypoints.length - 1) {
          final advanced = _moveToNextRouteOrComplete();
          if (!advanced) {
            break;
          }
        }
      }
    }

    await _publishCurrentBus();
  }

  bool _moveToNextRouteOrComplete() {
    if (_routeQueue.isEmpty) {
      return false;
    }

    if (_routeIndex < _routeQueue.length - 1) {
      _routeIndex++;
      _waypointIndex = 0;
      _distanceIntoSegmentMeters = 0;
      _currentLat = _routeQueue[_routeIndex].waypoints.first.latitude;
      _currentLon = _routeQueue[_routeIndex].waypoints.first.longitude;
      _syncStateForCurrentRoute(
        status: 'Driving route ${_routeIndex + 1} of ${_routeQueue.length}',
      );
      return true;
    }

    if (state.loopRoutes) {
      _routeIndex = 0;
      _waypointIndex = 0;
      _distanceIntoSegmentMeters = 0;
      _currentLat = _routeQueue.first.waypoints.first.latitude;
      _currentLon = _routeQueue.first.waypoints.first.longitude;
      state = state.copyWith(
        completedLoops: state.completedLoops + 1,
      );
      _syncStateForCurrentRoute(
        status:
            'Loop ${state.completedLoops + 1} started on ${_routeQueue.first.routeName}',
      );
      return true;
    }

    _completeSimulation();
    return false;
  }

  void _completeSimulation() {
    _simTimer?.cancel();
    _simTimer = null;
    final routeName =
        _routeQueue.isEmpty ? null : _routeQueue[_routeIndex].routeName;
    state = state.copyWith(
      isSimulating: false,
      hasDebugBus: true,
      currentRouteName: routeName,
      status: routeName == null
          ? 'Simulation completed'
          : 'Completed $routeName',
    );
  }

  Future<void> _publishCurrentBus() async {
    final route = _routeQueue.isEmpty ? null : _routeQueue[_routeIndex];
    final personCount = _personCount.clamp(0, Bus.maxPassengerCount).toInt();
    final seatsAvailable = max(0, Bus.maxPassengerCount - personCount);

    final payload = {
      'bus_mac': _debugBusMac,
      'bus_name': 'Debug Route Driver',
      'current_lat': _currentLat,
      'current_lon': _currentLon,
      'person_count': personCount,
      'seats_available': seatsAvailable,
      'pm2_5': 15.0 + _random.nextDouble() * 10,
      'pm10': 25.0 + _random.nextDouble() * 20,
      'temp': 28.0 + _random.nextDouble() * 5,
      'hum': 60.0 + _random.nextDouble() * 20,
      'is_online': true,
      'route_id': route?.routeId,
      'last_updated': DateTime.now().toIso8601String(),
    };

    await _api.sendFakeLocation(payload);

    final injectedBus = Bus(
      id: _debugBusMac,
      busMac: _debugBusMac,
      busName: '(Test) Debug Route Driver',
      currentLat: _currentLat,
      currentLon: _currentLon,
      personCount: personCount,
      seatsAvailable: seatsAvailable,
      pm25: payload['pm2_5'] as double,
      pm10: payload['pm10'] as double,
      temp: payload['temp'] as double,
      hum: payload['hum'] as double,
      isOnline: true,
      routeId: route?.routeId,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
      isFake: true,
    );

    _ref.read(dataProvider.notifier).updateBusLocally(injectedBus);
  }

  void _syncStateForCurrentRoute({String? status}) {
    if (_routeQueue.isEmpty) {
      return;
    }

    final route = _routeQueue[_routeIndex];
    state = state.copyWith(
      currentRouteId: route.routeId,
      currentRouteName: route.routeName,
      currentRouteIndex: _routeIndex,
      totalRoutes: _routeQueue.length,
      currentWaypointIndex: _waypointIndex,
      totalWaypoints: route.waypoints.length,
      status: status ??
          'Driving route ${_routeIndex + 1} of ${_routeQueue.length}',
      hasDebugBus: true,
      simulatingBusId: _debugBusMac,
    );
  }

  Future<void> _stopSimulation({
    required bool removeBus,
    required String status,
  }) async {
    _simTimer?.cancel();
    _simTimer = null;

    final busId = state.simulatingBusId;
    state = state.copyWith(
      isSimulating: false,
      hasDebugBus: removeBus ? false : state.hasDebugBus,
      status: status,
      clearRoute: removeBus,
      currentRouteIndex: 0,
      totalRoutes: removeBus ? 0 : state.totalRoutes,
      currentWaypointIndex: 0,
      totalWaypoints: removeBus ? 0 : state.totalWaypoints,
    );

    if (removeBus && busId != null) {
      _ref.read(dataProvider.notifier).removeBusLocally(busId);
      await _api.deleteFakeLocation(busId);
    }
  }

  double _lerp(double start, double end, double t) {
    return start + ((end - start) * t.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }
}

final simulationProvider =
    StateNotifierProvider<SimulationNotifier, SimulationState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return SimulationNotifier(api, ref);
});
