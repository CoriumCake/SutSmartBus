import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../providers/data_provider.dart';
import '../providers/debug_provider.dart';
import '../providers/language_provider.dart';
import '../utils/route_helpers.dart';
import '../widgets/bus_card.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  int _passengerCount = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchPassengerCount();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPassengerCount() async {
    final api = ref.read(apiServiceProvider);
    final count = await api.fetchPassengerCount();
    if (count != null && mounted) {
      setState(() => _passengerCount = count);
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(dataProvider.notifier).refreshBuses();
    await _fetchPassengerCount();
  }

  void _handleBusPress(Bus bus) {
    context.go('/map', extra: {
      'focusBus': bus,
    });
  }

  BusRouteInfo? _routeInfoForBus(Bus bus, List<BusRoute> routes) {
    final route = routes.length == 1
        ? routes.first
        : routes
            .where((candidate) => candidate.routeId == bus.routeId)
            .firstOrNull;
    if (route == null) {
      return null;
    }

    return BusRouteInfo(
      route: route,
      nextStop: findNextStop(
        bus.currentLat,
        bus.currentLon,
        route.waypoints,
      ),
    );
  }

  bool _matchesSearch(Bus bus, BusRouteInfo? routeInfo) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    return bus.busName.toLowerCase().contains(query) ||
        (routeInfo?.route.routeName.toLowerCase().contains(query) ?? false) ||
        (routeInfo?.nextStop?.stopName.toLowerCase().contains(query) ?? false);
  }

  bool _shouldShowBus(Bus bus, bool debugMode) {
    return debugMode || !bus.isDebugBus;
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final routes = ref.watch(routesProvider);
    final debugMode = ref.watch(debugProvider).debugMode;
    final theme = Theme.of(context);
    final t = ref.watch(languageProvider).t;
    final visibleBuses =
        buses.where((bus) => _shouldShowBus(bus, debugMode)).toList();
    final busCards = visibleBuses
        .map((bus) => (bus: bus, routeInfo: _routeInfoForBus(bus, routes)))
        .where((entry) => _matchesSearch(entry.bus, entry.routeInfo))
        .toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t('routes'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _searchController,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF111827),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search bus, route, or stop',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF64748B),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF64748B),
                        ),
                      ),
              ),
            ),
          ),
          Expanded(
            child: visibleBuses.isEmpty
                ? _buildEmptyState(theme)
                : busCards.isEmpty
                    ? _buildNoSearchResults(theme)
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: busCards.length,
                          itemBuilder: (context, index) {
                            final bus = busCards[index].bus;
                            final routeInfo = busCards[index].routeInfo;
                            return BusCard(
                              bus: bus,
                              routeInfo: routeInfo,
                              passengerCount: _passengerCount,
                              onTap: () => _handleBusPress(bus),
                              showActionButton: false,
                            );
                          },
                        ),
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
          Icon(Icons.directions_bus_outlined,
              size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text('No active buses', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            "Buses will appear here when they're online",
            style: theme.textTheme.bodySmall,
          ),
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

  Widget _buildNoSearchResults(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text('No matching buses', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Try a different bus name, route, or stop',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
