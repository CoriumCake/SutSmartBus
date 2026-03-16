import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import '../config/allowed_devices.dart';

class DebugState {
  final bool debugMode;
  final bool isDevMachine;
  final String? deviceId;
  final int apiCallCount;

  DebugState({
    this.debugMode = false,
    this.isDevMachine = false,
    this.deviceId,
    this.apiCallCount = 0,
  });

  DebugState copyWith({bool? debugMode, bool? isDevMachine, String? deviceId, int? apiCallCount}) {
    return DebugState(
      debugMode: debugMode ?? this.debugMode,
      isDevMachine: isDevMachine ?? this.isDevMachine,
      deviceId: deviceId ?? this.deviceId,
      apiCallCount: apiCallCount ?? this.apiCallCount,
    );
  }
}

class DebugNotifier extends StateNotifier<DebugState> {
  DebugNotifier() : super(DebugState()) {
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    final deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor;
    }

    final isAllowed = allowedDeviceIds.contains(deviceId);
    state = state.copyWith(
      deviceId: deviceId,
      isDevMachine: isAllowed,
      debugMode: isAllowed,
    );
  }

  void toggleDebug() {
    if (state.isDevMachine) {
      state = state.copyWith(debugMode: !state.debugMode);
    }
  }

  void incrementApiCount() {
    state = state.copyWith(apiCallCount: state.apiCallCount + 1);
  }
}

final debugProvider = StateNotifierProvider<DebugNotifier, DebugState>((ref) {
  return DebugNotifier();
});
