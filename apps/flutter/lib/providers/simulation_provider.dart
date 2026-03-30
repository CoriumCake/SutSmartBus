import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/bus.dart';
import 'data_provider.dart';

class SimulationState {
  final bool isSimulating;
  final String? simulatingBusId;

  SimulationState({
    this.isSimulating = false,
    this.simulatingBusId,
  });

  SimulationState copyWith({bool? isSimulating, String? simulatingBusId}) {
    return SimulationState(
      isSimulating: isSimulating ?? this.isSimulating,
      simulatingBusId: simulatingBusId ?? this.simulatingBusId,
    );
  }
}

class SimulationNotifier extends StateNotifier<SimulationState> {
  final ApiService _api;
  final Ref _ref;
  Timer? _simTimer;
  final Random _random = Random();
  int _personCount = 0;
  double _lastLat = 0;
  double _lastLon = 0;

  SimulationNotifier(this._api, this._ref) : super(SimulationState());

  void setPersonCount(int count) {
    _personCount = count;
  }

  void toggleSimulation(bool value, {double? lat, double? lon}) {
    if (value) {
      if (lat != null && lon != null) {
        _lastLat = lat;
        _lastLon = lon;
      }
      _startSimulation();
    } else {
      _stopSimulation();
    }
  }

  void updateLocation(double lat, double lon) {
    _lastLat = lat;
    _lastLon = lon;
    // Optional: could trigger instant update if simulating
    if (state.isSimulating) {
      // Just updating coordinates; next timer cycle or manual trigger will use them
    }
  }

  void _startSimulation() {
    final busId = 'DEBUG-BUS-01';
    state = state.copyWith(isSimulating: true, simulatingBusId: busId);
    
    // Send first update immediately
    _sendUpdate();

    _simTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _sendUpdate();
    });
  }

  Future<void> _sendUpdate() async {
    final personCount = _personCount;
    final lat = _lastLat != 0 ? _lastLat : 14.8816;
    final lon = _lastLon != 0 ? _lastLon : 102.0207;

    final payload = {
      'bus_mac': 'DEBUG-MAC-01',
      'bus_name': 'Debug Simulator 1',
      'current_lat': lat,
      'current_lon': lon,
      'person_count': personCount,
      'seats_available': _random.nextInt(40),
      'pm2_5': 15.0 + _random.nextDouble() * 10,
      'pm10': 30.0 + _random.nextDouble() * 20,
      'temp': 28.0 + _random.nextDouble() * 5,
      'hum': 60.0 + _random.nextDouble() * 20,
      'is_online': true,
      'last_updated': DateTime.now().toIso8601String(),
    };

    await _api.sendFakeLocation(payload);
    
    final injectedBus = Bus(
          id: 'DEBUG-MAC-01',
          busMac: 'DEBUG-MAC-01',
          busName: '(Test) Debug Simulator 1',
          currentLat: lat,
          currentLon: lon,
          personCount: personCount,
          seatsAvailable: payload['seats_available'] as int,
          pm25: payload['pm2_5'] as double,
          pm10: payload['pm10'] as double,
          temp: payload['temp'] as double,
          hum: payload['hum'] as double,
          isOnline: true,
          lastUpdated: DateTime.now().millisecondsSinceEpoch,
          isFake: true,
        );

    _ref.read(dataProvider.notifier).updateBusLocally(injectedBus);
    _ref.read(dataProvider.notifier).refreshBuses();
  }

  void _stopSimulation() async {
    final busId = state.simulatingBusId;
    _simTimer?.cancel();
    _simTimer = null;
    state = state.copyWith(isSimulating: false);
    
    if (busId != null) {
      _ref.read(dataProvider.notifier).removeBusLocally(busId);
      await _api.deleteFakeLocation(busId);
    }
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }
}

final simulationProvider = StateNotifierProvider<SimulationNotifier, SimulationState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return SimulationNotifier(api, ref);
});
