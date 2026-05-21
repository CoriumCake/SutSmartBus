import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

class DeveloperSettingsState {
  final bool resetPassengerCountAtTerminalStop;
  final bool noGpsModeEnabled;
  final String? assignedBusMac;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  const DeveloperSettingsState({
    required this.resetPassengerCountAtTerminalStop,
    required this.noGpsModeEnabled,
    this.assignedBusMac,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  DeveloperSettingsState copyWith({
    bool? resetPassengerCountAtTerminalStop,
    bool? noGpsModeEnabled,
    String? assignedBusMac,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool clearAssignedBusMac = false,
  }) {
    return DeveloperSettingsState(
      resetPassengerCountAtTerminalStop: resetPassengerCountAtTerminalStop ??
          this.resetPassengerCountAtTerminalStop,
      noGpsModeEnabled: noGpsModeEnabled ?? this.noGpsModeEnabled,
      assignedBusMac:
          clearAssignedBusMac ? null : (assignedBusMac ?? this.assignedBusMac),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DeveloperSettingsNotifier extends StateNotifier<DeveloperSettingsState> {
  DeveloperSettingsNotifier(this._apiService)
      : super(
          const DeveloperSettingsState(
            resetPassengerCountAtTerminalStop: true,
            noGpsModeEnabled: false,
            assignedBusMac: null,
            isLoading: true,
          ),
        ) {
    load();
  }

  final ApiService _apiService;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final settings = await _apiService.fetchDeveloperSettings();
      final resetAtTerminalStop =
          settings?['reset_passenger_count_at_terminal_stop'] as bool? ?? true;
      final noGpsModeEnabled =
          settings?['no_gps_mode_enabled'] as bool? ?? false;
      final assignedBusMac =
          (settings?['assigned_bus_mac'] as String?)?.trim().isNotEmpty == true
              ? (settings?['assigned_bus_mac'] as String).trim()
              : null;
      state = state.copyWith(
        resetPassengerCountAtTerminalStop: resetAtTerminalStop,
        noGpsModeEnabled: noGpsModeEnabled,
        assignedBusMac: assignedBusMac,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not load developer settings.',
      );
    }
  }

  Future<void> setResetPassengerCountAtTerminalStop(bool enabled) async {
    final previousValue = state.resetPassengerCountAtTerminalStop;
    state = state.copyWith(
      resetPassengerCountAtTerminalStop: enabled,
      isSaving: true,
      clearError: true,
    );

    try {
      final settings = await _apiService.updateDeveloperSettings(
        resetPassengerCountAtTerminalStop: enabled,
        noGpsModeEnabled: state.noGpsModeEnabled,
        assignedBusMac: state.assignedBusMac,
      );
      final resetAtTerminalStop =
          settings?['reset_passenger_count_at_terminal_stop'] as bool? ??
              enabled;
      final noGpsModeEnabled =
          settings?['no_gps_mode_enabled'] as bool? ?? state.noGpsModeEnabled;
      final assignedBusMac =
          (settings?['assigned_bus_mac'] as String?)?.trim().isNotEmpty == true
              ? (settings?['assigned_bus_mac'] as String).trim()
              : state.assignedBusMac;
      state = state.copyWith(
        resetPassengerCountAtTerminalStop: resetAtTerminalStop,
        noGpsModeEnabled: noGpsModeEnabled,
        assignedBusMac: assignedBusMac,
        isSaving: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        resetPassengerCountAtTerminalStop: previousValue,
        isSaving: false,
        errorMessage: 'Could not update developer settings.',
      );
    }
  }

  Future<void> setNoGpsModeEnabled(bool enabled) async {
    final previousValue = state.noGpsModeEnabled;
    state = state.copyWith(
      noGpsModeEnabled: enabled,
      isSaving: true,
      clearError: true,
    );

    try {
      final settings = await _apiService.updateDeveloperSettings(
        resetPassengerCountAtTerminalStop:
            state.resetPassengerCountAtTerminalStop,
        noGpsModeEnabled: enabled,
        assignedBusMac: state.assignedBusMac,
      );
      final resetAtTerminalStop =
          settings?['reset_passenger_count_at_terminal_stop'] as bool? ??
              state.resetPassengerCountAtTerminalStop;
      final nextNoGpsModeEnabled =
          settings?['no_gps_mode_enabled'] as bool? ?? enabled;
      final assignedBusMac =
          (settings?['assigned_bus_mac'] as String?)?.trim().isNotEmpty == true
              ? (settings?['assigned_bus_mac'] as String).trim()
              : state.assignedBusMac;
      state = state.copyWith(
        resetPassengerCountAtTerminalStop: resetAtTerminalStop,
        noGpsModeEnabled: nextNoGpsModeEnabled,
        assignedBusMac: assignedBusMac,
        isSaving: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        noGpsModeEnabled: previousValue,
        isSaving: false,
        errorMessage: 'Could not update developer settings.',
      );
    }
  }

  Future<void> setAssignedBusMac(String? busMac) async {
    final previousValue = state.assignedBusMac;
    final normalizedBusMac = busMac?.trim();
    state = state.copyWith(
      assignedBusMac: normalizedBusMac != null && normalizedBusMac.isNotEmpty
          ? normalizedBusMac
          : null,
      isSaving: true,
      clearError: true,
    );

    try {
      final settings = await _apiService.updateDeveloperSettings(
        resetPassengerCountAtTerminalStop:
            state.resetPassengerCountAtTerminalStop,
        noGpsModeEnabled: state.noGpsModeEnabled,
        assignedBusMac: normalizedBusMac ?? '',
      );
      final resetAtTerminalStop =
          settings?['reset_passenger_count_at_terminal_stop'] as bool? ??
              state.resetPassengerCountAtTerminalStop;
      final noGpsModeEnabled =
          settings?['no_gps_mode_enabled'] as bool? ?? state.noGpsModeEnabled;
      final nextAssignedBusMac =
          (settings?['assigned_bus_mac'] as String?)?.trim().isNotEmpty == true
              ? (settings?['assigned_bus_mac'] as String).trim()
              : null;
      state = state.copyWith(
        resetPassengerCountAtTerminalStop: resetAtTerminalStop,
        noGpsModeEnabled: noGpsModeEnabled,
        assignedBusMac: nextAssignedBusMac,
        isSaving: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        assignedBusMac: previousValue,
        isSaving: false,
        errorMessage: 'Could not update developer settings.',
      );
    }
  }
}

final developerSettingsProvider =
    StateNotifierProvider<DeveloperSettingsNotifier, DeveloperSettingsState>(
        (ref) {
  return DeveloperSettingsNotifier(ApiService());
});
