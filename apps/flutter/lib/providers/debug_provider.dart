import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'data_provider.dart';
// import '../config/allowed_devices.dart';

class DebugState {
  final bool debugMode;
  final bool randomTelemetryEnabled;
  final bool isDevMachine;
  final String? deviceId;
  final int apiCallCount;

  DebugState({
    this.debugMode = false,
    this.randomTelemetryEnabled = false,
    this.isDevMachine = false,
    this.deviceId,
    this.apiCallCount = 0,
  });

  DebugState copyWith(
      {bool? debugMode,
      bool? randomTelemetryEnabled,
      bool? isDevMachine,
      String? deviceId,
      int? apiCallCount}) {
    return DebugState(
      debugMode: debugMode ?? this.debugMode,
      randomTelemetryEnabled:
          randomTelemetryEnabled ?? this.randomTelemetryEnabled,
      isDevMachine: isDevMachine ?? this.isDevMachine,
      deviceId: deviceId ?? this.deviceId,
      apiCallCount: apiCallCount ?? this.apiCallCount,
    );
  }
}

class DebugNotifier extends StateNotifier<DebugState> {
  final Ref _ref;
  Timer? _telemetryTimer;

  DebugNotifier(this._ref) : super(DebugState()) {
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    final deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    if (kIsWeb) {
      // On web we could use other fields, but skip for now
    } else if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor;
    }

    final isAllowed =
        true; // Temporarily bypassed for testing so every user can access
    state = state.copyWith(
      deviceId: deviceId,
      isDevMachine: isAllowed,
      debugMode: isAllowed,
    );
  }

  void toggleDebug() {
    if (state.isDevMachine) {
      final enabled = !state.debugMode;
      if (!enabled) {
        _stopRandomTelemetry();
      }
      state = state.copyWith(
        debugMode: enabled,
        randomTelemetryEnabled: enabled ? state.randomTelemetryEnabled : false,
      );
    }
  }

  void toggleRandomTelemetry() {
    if (!state.isDevMachine || !state.debugMode) {
      return;
    }

    if (state.randomTelemetryEnabled) {
      _stopRandomTelemetry();
      state = state.copyWith(randomTelemetryEnabled: false);
    } else {
      state = state.copyWith(randomTelemetryEnabled: true);
      _startRandomTelemetry();
    }
  }

  void _startRandomTelemetry() {
    _telemetryTimer?.cancel();
    _randomizeTelemetry();
    _telemetryTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _randomizeTelemetry(),
    );
  }

  void _stopRandomTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void _randomizeTelemetry() {
    _ref.read(dataProvider.notifier).randomizeOnlineBusTelemetry();
  }

  void incrementApiCount() {
    state = state.copyWith(apiCallCount: state.apiCallCount + 1);
  }

  @override
  void dispose() {
    _stopRandomTelemetry();
    super.dispose();
  }
}

final debugProvider = StateNotifierProvider<DebugNotifier, DebugState>((ref) {
  return DebugNotifier(ref);
});
