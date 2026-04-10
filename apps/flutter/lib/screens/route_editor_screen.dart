import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../services/route_storage_service.dart';
import '../providers/theme_provider.dart';

class RouteEditorScreen extends ConsumerStatefulWidget {
  final String? routeId;
  const RouteEditorScreen({super.key, this.routeId});

  @override
  ConsumerState<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends ConsumerState<RouteEditorScreen> {
  final MapController _mapController = MapController();
  final _routeStorage = RouteStorageService();
  
  String _routeName = 'New Route';
  String _routeColor = '#F57C00';
  List<Waypoint> _waypoints = [];
  int? _selectedIndex;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.routeId != null) {
      _loadRoute();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRoute() async {
    final route = await _routeStorage.loadRoute(widget.routeId!);
    if (route != null && mounted) {
      setState(() {
        _routeName = route.routeName;
        _routeColor = route.routeColor;
        _waypoints = List.from(route.waypoints);
        _loading = false;
      });
      if (_waypoints.isNotEmpty) {
        _mapController.move(LatLng(_waypoints[0].latitude, _waypoints[0].longitude), 15.0);
      }
    }
  }

  void _addWaypoint(LatLng point) {
    setState(() {
      _waypoints.add(Waypoint(
        latitude: point.latitude,
        longitude: point.longitude,
        isStop: false,
      ));
      _selectedIndex = _waypoints.length - 1;
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
      _selectedIndex = null;
    });
  }

  void _toggleStop(int index) {
    setState(() {
      final wp = _waypoints[index];
      _waypoints[index] = Waypoint(
        latitude: wp.latitude,
        longitude: wp.longitude,
        isStop: !wp.isStop,
        stopName: !wp.isStop ? 'Stop ${_waypoints.where((w) => w.isStop).length + 1}' : null,
      );
    });
  }

  Future<void> _saveRoute() async {
    if (_waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route must have at least 2 points.')),
      );
      return;
    }

    final id = widget.routeId ?? 'route_${DateTime.now().millisecondsSinceEpoch}';
    final route = BusRoute(
      routeId: id,
      routeName: _routeName,
      routeColor: _routeColor,
      waypoints: _waypoints,
    );

    await _routeStorage.saveRoute(route);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route saved successfully.')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider).isDark;
    final theme = Theme.of(context);

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routeId == null ? 'Create Route' : 'Edit Route'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveRoute),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(14.8820, 102.0207),
              initialZoom: 15.0,
              onTap: (_, point) => _addWaypoint(point),
            ),
            children: [
              TileLayer(
                urlTemplate: isDark 
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _waypoints.map((w) => LatLng(w.latitude, w.longitude)).toList(),
                    color: _parseColor(_routeColor).withValues(alpha: 0.1),
                    strokeWidth: 4,
                  ),
                ],
              ),
              MarkerLayer(
                markers: _waypoints.asMap().entries.where((e) => e.value.isStop || _selectedIndex == e.key).map((entry) {
                  final i = entry.key;
                  final wp = entry.value;
                  final isSelected = _selectedIndex == i;

                  return Marker(
                    point: LatLng(wp.latitude, wp.longitude),
                    width: isSelected ? 40 : 20,
                    height: isSelected ? 40 : 20,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      onLongPress: () => _removeWaypoint(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: wp.isStop ? Colors.red : Colors.blue.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.yellow : (wp.isStop ? Colors.white : Colors.white.withValues(alpha: 0.3)),
                            width: isSelected ? 3 : 1.5,
                          ),
                        ),
                        child: wp.isStop 
                          ? const Icon(Icons.location_on, color: Colors.white, size: 12)
                          : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          
          // Floating Edit Panel
          if (_selectedIndex != null)
            _buildEditPanel(theme),

          // Route Settings Panel (Top)
          _buildTopSettings(theme),
        ],
      ),
    );
  }

  Widget _buildTopSettings(ThemeData theme) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Route Name', border: InputBorder.none),
                  controller: TextEditingController(text: _routeName)..selection = TextSelection.collapsed(offset: _routeName.length),
                  onChanged: (val) => _routeName = val,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: _showColorPicker,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: _parseColor(_routeColor), shape: BoxShape.circle, border: Border.all(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditPanel(ThemeData theme) {
    final wp = _waypoints[_selectedIndex!];
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Waypoint #${_selectedIndex! + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeWaypoint(_selectedIndex!),
                  ),
                ],
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Mark as Bus Stop'),
                subtitle: Text(wp.isStop ? (wp.stopName ?? 'Unnamed Stop') : 'Regular path point'),
                value: wp.isStop,
                onChanged: (_) => _toggleStop(_selectedIndex!),
              ),
              if (wp.isStop)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Stop Name'),
                    onChanged: (val) => setState(() {
                      _waypoints[_selectedIndex!] = Waypoint(
                        latitude: wp.latitude,
                        longitude: wp.longitude,
                        isStop: true,
                        stopName: val,
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPicker() {
    final colors = ['#F57C00', '#1976D2', '#4CAF50', '#E91E63', '#9C27B0', '#607D8B'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Route Color'),
        content: Wrap(
          spacing: 10,
          children: colors.map((c) => GestureDetector(
            onTap: () {
              setState(() => _routeColor = c);
              Navigator.pop(ctx);
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: _parseColor(c), shape: BoxShape.circle, border: Border.all(color: Colors.white)),
            ),
          )).toList(),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
