import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../providers/data_provider.dart';
import '../services/bus_mapping_service.dart';
import '../services/route_storage_service.dart';

class BusRouteAdminScreen extends ConsumerStatefulWidget {
  const BusRouteAdminScreen({super.key});

  @override
  ConsumerState<BusRouteAdminScreen> createState() => _BusRouteAdminScreenState();
}

class _BusRouteAdminScreenState extends ConsumerState<BusRouteAdminScreen> {
  final _busMappingService = BusMappingService();
  final _routeStorageService = RouteStorageService();
  
  Map<String, String> _mappings = {};
  List<BusRoute> _localRoutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final mappings = await _busMappingService.getAllMappings();
    final routes = await _routeStorageService.getAllRoutes();
    if (mounted) {
      setState(() {
        _mappings = mappings;
        _localRoutes = routes;
        _loading = false;
      });
    }
  }

  Future<void> _updateMapping(String busMac, String? routeId) async {
    if (routeId == null || routeId == 'none') {
      await _busMappingService.removeMapping(busMac);
    } else {
      await _busMappingService.saveMapping(busMac, routeId);
    }
    _loadData();
  }

  Future<void> _deleteRoute(BusRoute route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text('Are you sure you want to delete "${route.routeName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _routeStorageService.deleteRoute(route.routeId);
      _loadData();
    }
  }

  Future<void> _syncToServer() async {
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    int successCount = 0;
    
    // In this implementation, we sync all local routes to the server
    for (final route in _localRoutes) {
      final success = await api.syncRoute(route);
      if (success) successCount++;
    }

    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $successCount routes to server.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Route Administration'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Assignments', icon: Icon(Icons.assignment_ind_outlined)),
              Tab(text: 'Saved Routes', icon: Icon(Icons.map_outlined)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: _syncToServer,
              tooltip: 'Sync All to Server',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildAssignmentsTab(buses),
                  _buildRoutesTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildAssignmentsTab(List<Bus> buses) {
    if (buses.isEmpty) {
      return const Center(child: Text('No active buses found.'));
    }

    return ListView.builder(
      itemCount: buses.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final bus = buses[index];
        final currentRouteId = _mappings[bus.busMac];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_bus, size: 20),
                    const SizedBox(width: 8),
                    Text(bus.busName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    Text(bus.busMac, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Assigned Route:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _localRoutes.any((r) => r.routeId == currentRouteId) ? currentRouteId : 'none',
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'none', child: Text('None / Unassigned')),
                    ..._localRoutes.map((r) => DropdownMenuItem(
                          value: r.routeId,
                          child: Text(r.routeName),
                        )),
                  ],
                  onChanged: (val) => _updateMapping(bus.busMac, val),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoutesTab() {
    if (_localRoutes.isEmpty) {
      return const Center(child: Text('No local routes saved.'));
    }

    return ListView.builder(
      itemCount: _localRoutes.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final route = _localRoutes[index];
        return Card(
          child: ListTile(
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _parseColor(route.routeColor),
                shape: BoxShape.circle,
              ),
            ),
            title: Text(route.routeName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${route.waypoints.length} points, ${route.stops.length} stops'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteRoute(route),
            ),
          ),
        );
      },
    );
  }

  Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
