import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/bus.dart';
import '../providers/data_provider.dart';
import '../providers/developer_settings_provider.dart';

class DeveloperSettingsScreen extends ConsumerStatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  ConsumerState<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState
    extends ConsumerState<DeveloperSettingsScreen> {
  bool _isResettingPassengerCount = false;

  @override
  Widget build(BuildContext context) {
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
            child: ListTile(
              leading: Icon(
                Icons.person_remove_alt_1,
                color: assignedBus == null
                    ? theme.disabledColor
                    : theme.colorScheme.error,
              ),
              title: const Text('Reset passenger count'),
              subtitle: Text(
                assignedBus == null
                    ? 'Choose an assigned bus first.'
                    : 'Current count: ${assignedBus.personCount?.toString() ?? "--"}. Reset ${assignedBus.busName} to 0.',
              ),
              trailing: _isResettingPassengerCount
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: state.isLoading ||
                      state.isSaving ||
                      _isResettingPassengerCount ||
                      assignedBus == null
                  ? null
                  : () => _confirmResetPassengerCount(context, assignedBus),
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

  Future<void> _confirmResetPassengerCount(
    BuildContext context,
    Bus bus,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset passenger count?'),
        content: Text(
          'This will set ${bus.busName} to 0 passengers and send a reset command to the bus counter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    setState(() => _isResettingPassengerCount = true);
    final updatedBus =
        await ref.read(apiServiceProvider).resetDeveloperBusPassengerCount(
              bus.busMac,
            );
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() => _isResettingPassengerCount = false);

    if (updatedBus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reset passenger count.')),
      );
      return;
    }

    ref.read(dataProvider.notifier).updateBusLocally(updatedBus);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updatedBus.busName} passenger count reset.')),
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
