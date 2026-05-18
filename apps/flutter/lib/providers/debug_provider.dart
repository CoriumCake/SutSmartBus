import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;

class DebugState {
  final bool debugMode;
  final bool randomTelemetryEnabled;
  final bool isDevMachine;
  final String? deviceId;
  final int apiCallCount;

  const DebugState({
    this.debugMode = false,
    this.randomTelemetryEnabled = false,
    this.isDevMachine = false,
    this.deviceId,
    this.apiCallCount = 0,
  });

  DebugState copyWith({
    bool? debugMode,
    bool? randomTelemetryEnabled,
    bool? isDevMachine,
    String? deviceId,
    int? apiCallCount,
  }) {
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
  DebugNotifier() : super(const DebugState()) {
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    if (kIsWeb) {
      deviceId = null;
    } else if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor;
    }

    state = state.copyWith(deviceId: deviceId);
  }

  void incrementApiCount() {
    state = state.copyWith(apiCallCount: state.apiCallCount + 1);
  }
}

final debugProvider = StateNotifierProvider<DebugNotifier, DebugState>((ref) {
  return DebugNotifier();
});
