import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/bus.dart';
import '../providers/data_provider.dart';
import '../providers/developer_settings_provider.dart';

class DeveloperSettingsScreen extends ConsumerWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(developerSettingsProvider);
    final buses = ref.watch(busesProvider);
    final assignedBus = state.assignedBusMac == null
        ? null
        : buses.where((bus) => bus.busMac == state.assignedBusMac).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Developer Tools',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Experimental tools and operational controls for development builds.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                Icons.directions_bus,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Assigned bus'),
              subtitle: Text(
                assignedBus != null
                    ? '${assignedBus.busName} (${assignedBus.busMac})'
                    : state.assignedBusMac != null
                        ? state.assignedBusMac!
                        : 'Choose which bus receives no-GPS PM, count, and phone-location updates.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: state.isLoading || state.isSaving
                  ? null
                  : () => _showAssignedBusPicker(
                        context,
                        ref,
                        buses,
                        state.assignedBusMac,
                      ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              value: state.noGpsModeEnabled,
              onChanged: state.isLoading || state.isSaving
                  ? null
                  : (value) {
                      ref
                          .read(developerSettingsProvider.notifier)
                          .setNoGpsModeEnabled(value);
                    },
              secondary: Icon(
                Icons.gps_off,
                color: theme.colorScheme.primary,
              ),
              title: const Text('No GPS mode'),
              subtitle: Text(
                state.isLoading
                    ? 'Loading current server behavior...'
                    : state.noGpsModeEnabled
                        ? 'PM GPS is ignored. The assigned bus follows your phone location while passenger and PM readings still update.'
                        : 'Bus location follows PM GPS as usual.',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              value: state.resetPassengerCountAtTerminalStop,
              onChanged: state.isLoading || state.isSaving
                  ? null
                  : (value) {
                      ref
                          .read(developerSettingsProvider.notifier)
                          .setResetPassengerCountAtTerminalStop(value);
                    },
              secondary: Icon(
                Icons.restart_alt,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Reset bus count at final stop'),
              subtitle: Text(
                state.isLoading
                    ? 'Loading current server behavior...'
                    : state.resetPassengerCountAtTerminalStop
                        ? 'Passenger count resets automatically when the bus reaches the terminal stop.'
                        : 'Passenger count stays unchanged when the bus reaches the terminal stop.',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                Icons.wifi_tethering,
                color: theme.colorScheme.primary,
              ),
              title: const Text('SUT-IoT WiFi Heatmap'),
              subtitle:
                  const Text('Test route coverage from bus RSSI readings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/wifi-heatmap'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAssignedBusPicker(
    BuildContext context,
    WidgetRef ref,
    List<Bus> buses,
    String? selectedBusMac,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final sortedBuses = [...buses]
          ..sort((a, b) => a.busName.toLowerCase().compareTo(
                b.busName.toLowerCase(),
              ));
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('No assigned bus'),
                subtitle: const Text('Disable explicit assignment'),
                trailing: selectedBusMac == null
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  ref
                      .read(developerSettingsProvider.notifier)
                      .setAssignedBusMac(null);
                },
              ),
              for (final bus in sortedBuses)
                ListTile(
                  leading: const Icon(Icons.directions_bus),
                  title: Text(bus.busName),
                  subtitle: Text(bus.busMac),
                  trailing: selectedBusMac == bus.busMac
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    ref
                        .read(developerSettingsProvider.notifier)
                        .setAssignedBusMac(bus.busMac);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
