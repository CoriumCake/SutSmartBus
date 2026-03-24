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
    await ref.read(dataProvider.notifier).refreshBuses();
    await _fetchPassengerCount();
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
