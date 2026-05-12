import 'dart:async';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mqtt_service.dart';
import 'data_provider.dart';

// ─── Preset camera URLs ────────────────────────────────────────────────────────
const List<String> kCamUrls = [
  'http://192.168.1.100/stream',
  'http://192.168.1.101/stream',
  'rtsp://cam.example.com/live',
  'http://cam.example.com/mjpeg',
];

// ─── Preset simulated user positions (dx, dy within the mini-map canvas) ───────
const List<Offset> kPresetPositions = [
  Offset(60, 60),
  Offset(140, 80),
  Offset(200, 140),
  Offset(120, 180),
  Offset(50, 150),
];

// ─── State ─────────────────────────────────────────────────────────────────────
class TestModeState {
  final bool enabled;
  final String? selectedCamUrl;
  final int simulatedPersonCount;
  final Offset? simulatedUserPosition;

  const TestModeState({
    this.enabled = false,
    this.selectedCamUrl,
    this.simulatedPersonCount = 0,
    this.simulatedUserPosition,
  });

  TestModeState copyWith({
    bool? enabled,
    String? selectedCamUrl,
    int? simulatedPersonCount,
    Offset? simulatedUserPosition,
    bool clearCamUrl = false,
  }) {
    return TestModeState(
      enabled: enabled ?? this.enabled,
      selectedCamUrl:
          clearCamUrl ? null : (selectedCamUrl ?? this.selectedCamUrl),
      simulatedPersonCount: simulatedPersonCount ?? this.simulatedPersonCount,
      simulatedUserPosition:
          simulatedUserPosition ?? this.simulatedUserPosition,
    );
  }
}

// ─── Notifier ──────────────────────────────────────────────────────────────────
class TestModeNotifier extends StateNotifier<TestModeState> {
  final MqttService _mqtt;

  Timer? _positionTimer;
  int _positionIndex = 0;

  TestModeNotifier(this._mqtt) : super(const TestModeState());

  /// Toggle test mode on/off.
  void toggle({double? initialLat, double? initialLon}) {
    if (state.enabled) {
      _disable();
    } else {
      _enable(initialLat, initialLon);
    }
  }

  /// Select a camera URL to monitor.
  void selectCam(String url) {
    state = state.copyWith(selectedCamUrl: url);
  }

  /// Called externally to update the simulated person count (e.g. from MQTT).
  void updatePersonCount(int count) {
    state = state.copyWith(simulatedPersonCount: count);
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  void _enable(double? initialLat, double? initialLon) {
    state = state.copyWith(
      enabled: true,
      selectedCamUrl: kCamUrls.first,
      simulatedPersonCount: 0,
      simulatedUserPosition: kPresetPositions.first,
    );

    // Subscribe to the ESP32-CAM person-count MQTT topic
    _mqtt.subscribeToCamCount(_onCamCount);

    // Start periodic position cycling
    _positionIndex = 0;
    _positionTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _positionIndex = (_positionIndex + 1) % kPresetPositions.length;
      state = state.copyWith(
          simulatedUserPosition: kPresetPositions[_positionIndex]);
    });

    if (kDebugMode) {
      print('[TestModeNotifier] Test mode ENABLED');
    }
  }

  void _disable() {
    _positionTimer?.cancel();
    _positionTimer = null;

    _mqtt.unsubscribeFromCamCount();

    state = state.copyWith(
      enabled: false,
      simulatedPersonCount: 0,
      clearCamUrl: true,
    );

    if (kDebugMode) {
      print('[TestModeNotifier] Test mode DISABLED');
    }
  }

  void _onCamCount(int count) {
    if (state.enabled) {
      state = state.copyWith(simulatedPersonCount: count);
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _mqtt.unsubscribeFromCamCount();
    super.dispose();
  }
}

// ─── Provider ──────────────────────────────────────────────────────────────────
final testModeProvider =
    StateNotifierProvider<TestModeNotifier, TestModeState>((ref) {
  final mqtt = ref.watch(mqttServiceProvider);
  return TestModeNotifier(mqtt);
});
