import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bus.dart';
import '../providers/data_provider.dart';
import '../providers/debug_provider.dart';
import '../widgets/wifi_heatmap_map.dart';

class WifiHeatmapScreen extends ConsumerStatefulWidget {
  const WifiHeatmapScreen({super.key});

  @override
  ConsumerState<WifiHeatmapScreen> createState() => _WifiHeatmapScreenState();
}

class _WifiHeatmapScreenState extends ConsumerState<WifiHeatmapScreen> {
  String _timeRange = '1h';

  @override
  Widget build(BuildContext context) {
    final List<Bus> buses = ref.watch(busesProvider);
    final bool debugMode = ref.watch(debugProvider).debugMode;
    final List<Bus> visibleBuses =
        debugMode ? buses : buses.where((bus) => !bus.isDebugBus).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SUT-IoT WiFi Heatmap'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: WifiHeatmapMapWidget(
              buses: visibleBuses,
              timeRange: _timeRange,
              onTimeRangeChanged: (range) => setState(() => _timeRange = range),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    offset: const Offset(0, -2),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'Live WiFi Readings',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visibleBuses.length,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemBuilder: (context, index) =>
                          _buildWifiCard(visibleBuses[index], theme),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiCard(Bus bus, ThemeData theme) {
    final status = _wifiStatus(bus);

    return Opacity(
      opacity: bus.isOffline ? 0.55 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          leading: Icon(status.icon, color: status.color),
          title: Text(
            bus.busName,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(bus.currentLat == null || bus.currentLon == null
              ? 'Waiting for GPS location'
              : 'RSSI: ${bus.rssi?.toString() ?? "--"} dBm'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              status.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({Color color, IconData icon, String label}) _wifiStatus(Bus bus) {
    if (bus.isOffline || bus.rssi == null || bus.rssi! <= -90) {
      return (
        color: Colors.red,
        icon: Icons.signal_wifi_off,
        label: 'NO WIFI',
      );
    }
    if (bus.rssi! >= -70) {
      return (
        color: Colors.green,
        icon: Icons.signal_wifi_4_bar,
        label: 'GOOD',
      );
    }
    return (
      color: Colors.orange,
      icon: Icons.network_wifi_2_bar,
      label: 'WEAK',
    );
  }
}
