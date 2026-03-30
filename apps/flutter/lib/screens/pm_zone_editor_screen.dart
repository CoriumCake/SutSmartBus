import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/data_provider.dart';

class PMZoneEditorScreen extends ConsumerStatefulWidget {
  const PMZoneEditorScreen({super.key});

  @override
  ConsumerState<PMZoneEditorScreen> createState() => _PMZoneEditorScreenState();
}

class _PMZoneEditorScreenState extends ConsumerState<PMZoneEditorScreen> {
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _zones = [];
  bool _isLoading = true;

  Map<String, dynamic>? _selectedZone;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController();
  
  // SUT Center
  final LatLng _center = const LatLng(14.8789, 102.0163);

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nameController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _loadZones() async {
    setState(() => _isLoading = true);
    try {
      final zones = await ref.read(apiServiceProvider).fetchPMZones();
      setState(() {
        _zones = zones;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load PM Zones')),
        );
      }
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_selectedZone != null && _selectedZone!['id'] == null) {
      // We are creating a new zone, update its location
      setState(() {
        _selectedZone!['lat'] = point.latitude;
        _selectedZone!['lon'] = point.longitude;
      });
    } else {
      // Deselect or create new
      _startNewZone(point);
    }
  }

  void _startNewZone(LatLng point) {
    setState(() {
      _selectedZone = {
        'name': 'New Zone',
        'lat': point.latitude,
        'lon': point.longitude,
        'radius': 300,
      };
      _nameController.text = 'New Zone';
      _radiusController.text = '300';
    });
  }

  void _selectZone(Map<String, dynamic> zone) {
    setState(() {
      _selectedZone = Map.from(zone);
      _nameController.text = _selectedZone!['name'] ?? '';
      _radiusController.text = _selectedZone!['radius']?.toString() ?? '300';
      _mapController.move(LatLng(zone['lat'], zone['lon']), _mapController.camera.zoom);
    });
  }

  Future<void> _saveZone() async {
    if (_selectedZone == null) return;
    
    final name = _nameController.text.trim();
    final radius = int.tryParse(_radiusController.text.trim()) ?? 300;
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zone name is required')),
      );
      return;
    }

    final zoneData = {
      'name': name,
      'lat': _selectedZone!['lat'],
      'lon': _selectedZone!['lon'],
      'radius': radius,
    };

    final isNew = _selectedZone!['id'] == null;
    
    // Show Loading
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    bool success;
    if (isNew) {
      success = await ref.read(apiServiceProvider).createPMZone(zoneData);
    } else {
      success = await ref.read(apiServiceProvider).updatePMZone(_selectedZone!['id'].toString(), zoneData);
    }

    if (mounted) {
      Navigator.pop(context); // Close loading
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zone ${isNew ? 'created' : 'updated'} successfully')),
        );
        setState(() => _selectedZone = null);
        _loadZones();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save PM Zone')),
        );
      }
    }
  }

  Future<void> _deleteZone() async {
    if (_selectedZone == null || _selectedZone!['id'] == null) {
      setState(() => _selectedZone = null);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Zone?'),
        content: Text('Are you sure you want to delete "${_selectedZone!['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    final success = await ref.read(apiServiceProvider).deletePMZone(_selectedZone!['id'].toString());

    if (mounted) {
      Navigator.pop(context); // Close loading
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zone deleted!')),
        );
        setState(() => _selectedZone = null);
        _loadZones();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete PM Zone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Build Circles and Markers
    final circles = <CircleMarker>[];
    final markers = <Marker>[];

    // Existing Zones
    for (final zone in _zones) {
      final isSelected = _selectedZone != null && _selectedZone!['id'] == zone['id'];
      
      // Don't draw the existing zone if it is currently being edited
      if (isSelected) continue;

      final point = LatLng(zone['lat'] as double, zone['lon'] as double);
      final radius = (zone['radius'] as num).toDouble();

      circles.add(CircleMarker(
        point: point,
        color: Colors.blue.withValues(alpha: 0.3),
        borderColor: Colors.blue,
        borderStrokeWidth: 2,
        useRadiusInMeter: true,
        radius: radius,
      ));

      markers.add(Marker(
        point: point,
        width: 100,
        height: 40,
        child: GestureDetector(
          onTap: () => _selectZone(zone),
          child: Column(
            children: [
              const Icon(Icons.location_on, color: Colors.blue, size: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.white70,
                child: Text(zone['name'] ?? 'Zone', style: const TextStyle(fontSize: 10, color: Colors.black)),
              )
            ],
          ),
        ),
      ));
    }

    // Selected/New Zone
    if (_selectedZone != null) {
      final lat = _selectedZone!['lat'] as double;
      final lon = _selectedZone!['lon'] as double;
      final point = LatLng(lat, lon);
      final radiusRaw = int.tryParse(_radiusController.text);
      final radius = (radiusRaw ?? _selectedZone!['radius'] as num).toDouble();

      circles.add(CircleMarker(
        point: point,
        color: Colors.orange.withValues(alpha: 0.4),
        borderColor: Colors.orange,
        borderStrokeWidth: 3,
        useRadiusInMeter: true,
        radius: radius,
      ));

      markers.add(Marker(
        point: point,
        width: 120,
        height: 60,
        child: Column(
          children: [
            const Icon(Icons.api, color: Colors.orange, size: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.orange[100],
              child: Text(_nameController.text.isNotEmpty ? _nameController.text : 'New Zone', 
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
            )
          ],
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PM Zones Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadZones,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 15.0,
                onTap: _onMapTap,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.sut.smartbus',
                ),
                CircleLayer(circles: circles),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          
          if (_selectedZone != null)
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedZone!['id'] == null ? 'Create New Zone' : 'Edit Zone',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('Tap anywhere on the map to set the zone center.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(labelText: 'Zone Name', border: OutlineInputBorder()),
                              onChanged: (_) => setState((){}),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _radiusController,
                              decoration: const InputDecoration(labelText: 'Radius (meters)', border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState((){}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _deleteZone,
                            child: Text(_selectedZone!['id'] == null ? 'Cancel' : 'Delete', style: const TextStyle(color: Colors.red)),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _saveZone,
                            icon: const Icon(Icons.save),
                            label: const Text('Save Zone'),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text(
                'Tap on a zone marker to edit, or tap anywhere on the map to create a new zone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
        ],
      ),
    );
  }
}
