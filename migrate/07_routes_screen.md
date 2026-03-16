# 07 — Routes Screen Migration

## Purpose
Migrate `RoutesScreen.js` (417 lines) — the bus list with route assignments, next-stop indicators, and ETA badges.

## Source File
- `screens/RoutesScreen.js` → `lib/screens/routes_screen.dart` + `lib/widgets/bus_card.dart`

---

## Current React Native Behavior

1. Displays a header: "Routes" + active bus count banner
2. Lists all active buses as cards, each showing:
   - Bus name + WiFi signal icon + offline badge
   - Assigned route name
   - "Next Stop" pill with ETA badge
   - Stats row: PM2.5 level, passenger count
3. Pull-to-refresh syncs buses + routes from server
4. Debug mode shows saved routes as horizontal chips
5. Tapping a bus navigates to MapScreen with route + bus focus

---

## Flutter Implementation

### `lib/screens/routes_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/data_provider.dart';
import '../providers/debug_provider.dart';
import '../providers/language_provider.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../services/route_storage_service.dart';
import '../services/bus_mapping_service.dart';
import '../utils/route_helpers.dart';
import '../widgets/bus_card.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  Map<String, BusRouteInfo> _busRoutes = {};
  List<BusRoute> _localRoutes = [];
  int _passengerCount = 0;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadLocalRoutes();
    _fetchPassengerCount();
  }

  Future<void> _loadLocalRoutes() async {
    final storage = RouteStorageService();
    final routes = await storage.getAllRoutes();
    setState(() => _localRoutes = routes);
  }

  Future<void> _fetchPassengerCount() async {
    final api = ref.read(apiServiceProvider);
    final count = await api.fetchPassengerCount();
    if (count != null && mounted) {
      setState(() => _passengerCount = count);
    }
  }

  Future<void> _calculateBusRoutes(List<Bus> buses) async {
    final mappingService = BusMappingService();
    final storageService = RouteStorageService();
    final mappings = await mappingService.getAllMappings();
    final routeMap = <String, BusRouteInfo>{};

    for (final bus in buses) {
      final routeId = mappings[bus.busMac];
      if (routeId != null) {
        final route = await storageService.loadRoute(routeId);
        if (route != null) {
          final nextStop = findNextStop(
            bus.currentLat, bus.currentLon, route.waypoints,
          );
          routeMap[bus.busMac] = BusRouteInfo(route: route, nextStop: nextStop);
        }
      }
    }

    if (mounted) setState(() => _busRoutes = routeMap);
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    await ref.read(dataProvider.notifier).refreshBuses();
    await _fetchPassengerCount();
    setState(() => _refreshing = false);
  }

  void _handleBusPress(Bus bus) {
    final routeInfo = _busRoutes[bus.busMac];
    context.go('/map', extra: {
      'selectedRoute': routeInfo?.route,
      'focusBus': bus,
    });
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final debugMode = ref.watch(debugProvider).debugMode;
    final theme = Theme.of(context);
    final t = ref.watch(languageProvider).t;

    // Recalculate bus routes when buses change
    ref.listen(busesProvider, (prev, next) {
      _calculateBusRoutes(next);
    });

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t('routes'),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                if (debugMode)
                  IconButton(
                    icon: Icon(Icons.add_circle, color: theme.colorScheme.primary, size: 28),
                    onPressed: () => context.push('/route-editor'),
                  ),
              ],
            ),
          ),

          // Bus count banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_bus, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${buses.length} active ${buses.length == 1 ? "bus" : "buses"}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          // Bus list
          Expanded(
            child: buses.isEmpty
                ? _buildEmptyState(theme)
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: buses.length,
                      itemBuilder: (context, index) {
                        final bus = buses[index];
                        final routeInfo = _busRoutes[bus.busMac];
                        return BusCard(
                          bus: bus,
                          routeInfo: routeInfo,
                          passengerCount: _passengerCount,
                          onTap: () => _handleBusPress(bus),
                        );
                      },
                    ),
                  ),
          ),

          // Debug: Saved routes chips
          if (debugMode && _localRoutes.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📁 Saved Routes (${_localRoutes.length})',
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _localRoutes.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(_localRoutes[i].routeName),
                          onPressed: () => context.push(
                            '/route-editor?routeId=${_localRoutes[i].routeId}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_bus_outlined, size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text('No active buses', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text("Buses will appear here when they're online",
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            onPressed: _onRefresh,
          ),
        ],
      ),
    );
  }
}
```

### `lib/widgets/bus_card.dart`

```dart
import 'package:flutter/material.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../utils/route_helpers.dart';

class BusRouteInfo {
  final BusRoute route;
  final NextStopResult? nextStop;
  BusRouteInfo({required this.route, this.nextStop});
}

class BusCard extends StatelessWidget {
  final Bus bus;
  final BusRouteInfo? routeInfo;
  final int passengerCount;
  final VoidCallback onTap;

  const BusCard({
    super.key,
    required this.bus,
    this.routeInfo,
    this.passengerCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOffline = bus.isOffline;

    return Opacity(
      opacity: isOffline ? 0.5 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header row: icon + name + chevron
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.directions_bus, size: 28,
                          color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${bus.busName}${isOffline ? " (Offline)" : ""}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (bus.rssi != null) ...[
                                const SizedBox(width: 8),
                                _buildSignalIcon(bus.rssi!),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (routeInfo != null)
                            Text('🛣️ ${routeInfo!.route.routeName}',
                                style: TextStyle(color: theme.colorScheme.primary, fontSize: 14))
                          else
                            Text('No route assigned',
                                style: TextStyle(color: theme.disabledColor,
                                    fontSize: 13, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.disabledColor),
                  ],
                ),

                // Next stop pill
                if (routeInfo?.nextStop != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('Next Stop: ', style: theme.textTheme.bodySmall),
                        Expanded(
                          child: Text(routeInfo!.nextStop!.stopName,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        if (routeInfo!.nextStop!.etaMinutes != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('~${routeInfo!.nextStop!.etaMinutes} min',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                ],

                // Stats row
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (bus.pm25 != null) ...[
                      Icon(Icons.eco, size: 14, color: Colors.green[600]),
                      const SizedBox(width: 4),
                      Text('PM2.5: ${bus.pm25!.toStringAsFixed(1)}',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(width: 16),
                    ],
                    Icon(Icons.people, size: 14, color: Colors.purple[400]),
                    const SizedBox(width: 4),
                    Text('Passengers: $passengerCount/33',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignalIcon(int rssi) {
    IconData icon;
    Color color;
    if (rssi >= -55) { icon = Icons.signal_wifi_4_bar; color = const Color(0xFF10B981); }
    else if (rssi >= -65) { icon = Icons.network_wifi_3_bar; color = const Color(0xFF10B981); }
    else if (rssi >= -75) { icon = Icons.network_wifi_2_bar; color = const Color(0xFFF59E0B); }
    else if (rssi >= -85) { icon = Icons.network_wifi_1_bar; color = const Color(0xFFF97316); }
    else { icon = Icons.signal_wifi_0_bar; color = const Color(0xFFEF4444); }
    return Icon(icon, size: 20, color: color);
  }
}
```

---

## Verification Checklist

- [ ] Routes screen shows header with title and active bus count
- [ ] Bus cards render with name, route, signal icon, and offline badge
- [ ] Next stop pill displays stop name and ETA
- [ ] Stats row shows PM2.5 and passenger count
- [ ] Pull-to-refresh works
- [ ] Tapping a bus navigates to MapScreen with route/bus data
- [ ] Empty state shows when no buses are active
- [ ] Debug mode shows saved routes as horizontal chips
