import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../services/route_storage_service.dart';

class RouteEditorScreen extends StatefulWidget {
  final BusRoute? route;

  const RouteEditorScreen({super.key, this.route});

  @override
  State<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends State<RouteEditorScreen> {
  final MapController _mapController = MapController();
  final RouteStorageService _storage = RouteStorageService();
  final TextEditingController _routeNameController = TextEditingController();

  late String _routeColor;
  late List<Waypoint> _waypoints;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _routeNameController.text = widget.route?.routeName ?? 'New Route';
    _routeColor = widget.route?.routeColor ?? '#ef4444';
    _waypoints = List<Waypoint>.from(widget.route?.waypoints ?? []);
  }

  @override
  void dispose() {
    _routeNameController.dispose();
    super.dispose();
  }

  void _addWaypoint(LatLng point) {
    setState(() {
      _waypoints.add(
        Waypoint(latitude: point.latitude, longitude: point.longitude),
      );
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
    final waypoint = _waypoints[index];
    setState(() {
      _waypoints[index] = Waypoint(
        latitude: waypoint.latitude,
        longitude: waypoint.longitude,
        isStop: !waypoint.isStop,
        stopName: !waypoint.isStop
            ? 'Stop ${_waypoints.where((waypoint) => waypoint.isStop).length + 1}'
            : null,
      );
    });
  }

  Future<void> _saveRoute() async {
    if (_waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route must contain at least two points.'),
        ),
      );
      return;
    }

    final route = BusRoute(
      routeId:
          widget.route?.routeId ??
          'route_${DateTime.now().millisecondsSinceEpoch}',
      routeName: _routeNameController.text.trim().isEmpty
          ? 'Unnamed Route'
          : _routeNameController.text.trim(),
      routeColor: _routeColor,
      waypoints: _waypoints,
    );

    await _storage.saveRoute(route);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route == null ? 'Create Route' : 'Edit Route'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveRoute),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _waypoints.isNotEmpty
                  ? LatLng(
                      _waypoints.first.latitude,
                      _waypoints.first.longitude,
                    )
                  : const LatLng(14.8820, 102.0207),
              initialZoom: 15,
              onTap: (_, point) => _addWaypoint(point),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _waypoints
                        .map(
                          (waypoint) =>
                              LatLng(waypoint.latitude, waypoint.longitude),
                        )
                        .toList(),
                    color: _parseColor(_routeColor),
                    strokeWidth: 5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: _waypoints.asMap().entries.map((entry) {
                  final index = entry.key;
                  final waypoint = entry.value;
                  final isSelected = _selectedIndex == index;

                  return Marker(
                    point: LatLng(waypoint.latitude, waypoint.longitude),
                    width: isSelected ? 36 : 20,
                    height: isSelected ? 36 : 20,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = index),
                      onLongPress: () => _removeWaypoint(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: waypoint.isStop ? Colors.red : Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.amber : Colors.white,
                            width: isSelected ? 3 : 2,
                          ),
                        ),
                        child: waypoint.isStop
                            ? const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 12,
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _routeNameController,
                        decoration: const InputDecoration(
                          hintText: 'Route name',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickColor,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _parseColor(_routeColor),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_selectedIndex != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _buildWaypointEditor(),
            ),
        ],
      ),
    );
  }

  Widget _buildWaypointEditor() {
    final waypoint = _waypoints[_selectedIndex!];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Waypoint ${_selectedIndex! + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeWaypoint(_selectedIndex!),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bus stop'),
              subtitle: Text(
                waypoint.isStop
                    ? (waypoint.stopName ?? 'Unnamed stop')
                    : 'Path point',
              ),
              value: waypoint.isStop,
              onChanged: (_) => _toggleStop(_selectedIndex!),
            ),
            if (waypoint.isStop)
              TextField(
                decoration: const InputDecoration(labelText: 'Stop name'),
                controller: TextEditingController(
                  text: waypoint.stopName ?? '',
                ),
                onChanged: (value) {
                  setState(() {
                    _waypoints[_selectedIndex!] = Waypoint(
                      latitude: waypoint.latitude,
                      longitude: waypoint.longitude,
                      isStop: true,
                      stopName: value,
                    );
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickColor() async {
    const colors = [
      '#ef4444',
      '#2563eb',
      '#16a34a',
      '#d97706',
      '#db2777',
      '#7c3aed',
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select route color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                setState(() => _routeColor = color);
                Navigator.of(dialogContext).pop();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _parseColor(color),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    var normalized = hex.replaceFirst('#', '');
    if (normalized.length == 6) normalized = 'FF$normalized';
    return Color(int.parse(normalized, radix: 16));
  }
}
