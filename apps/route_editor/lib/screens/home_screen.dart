import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../services/api_service.dart';
import '../services/route_storage_service.dart';
import 'route_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RouteStorageService _storage = RouteStorageService();
  final ApiService _api = ApiService();
  List<BusRoute> _routes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final routes = await _storage.getAllRoutes();
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loading = false;
    });
  }

  Future<void> _openEditor([BusRoute? route]) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RouteEditorScreen(route: route)));
    await _loadRoutes();
  }

  Future<void> _importJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    String content = '';
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content.isEmpty) return;

    final decoded = jsonDecode(content);
    List<dynamic> rawWaypoints = [];
    var suggestedName = file.name.replaceAll('.json', '');

    if (decoded is List) {
      rawWaypoints = decoded;
    } else if (decoded is Map<String, dynamic>) {
      rawWaypoints = (decoded['waypoints'] as List?) ?? [];
      suggestedName = (decoded['routeName'] ?? decoded['name'] ?? suggestedName)
          .toString();
    }

    if (!mounted) return;
    final routeNameController = TextEditingController(text: suggestedName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import Route JSON'),
        content: TextField(
          controller: routeNameController,
          decoration: const InputDecoration(labelText: 'Route name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true || routeNameController.text.trim().isEmpty) return;

    final route = BusRoute(
      routeId: 'route_${DateTime.now().millisecondsSinceEpoch}',
      routeName: routeNameController.text.trim(),
      waypoints: rawWaypoints
          .map(
            (json) => Waypoint.fromJson(Map<String, dynamic>.from(json as Map)),
          )
          .toList(),
      routeColor: '#ef4444',
    );
    await _storage.saveRoute(route);
    await _loadRoutes();
  }

  Future<void> _syncRoute(BusRoute route) async {
    final success = await _api.syncRoute(route);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Synced "${route.routeName}" to server.'
              : 'Failed to sync "${route.routeName}".',
        ),
      ),
    );
  }

  Future<void> _pullFromServer() async {
    setState(() => _loading = true);
    final routes = await _api.fetchRoutes();
    if (routes.isNotEmpty) {
      await _storage.replaceAll(routes);
    }
    await _loadRoutes();
  }

  Future<void> _deleteRoute(BusRoute route) async {
    await _storage.deleteRoute(route.routeId);
    await _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SUT Route Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Pull current route from server',
            onPressed: _pullFromServer,
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: 'Import route JSON',
            onPressed: _importJson,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Route'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
          ? const Center(
              child: Text('No saved routes yet. Import JSON or create one.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _routes.length,
              itemBuilder: (context, index) {
                final route = _routes[index];
                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _parseColor(route.routeColor),
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(route.routeName),
                    subtitle: Text(
                      '${route.waypoints.length} points • ${route.stops.length} stops',
                    ),
                    onTap: () => _openEditor(route),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.cloud_upload_outlined),
                          tooltip: 'Sync to server',
                          onPressed: () => _syncRoute(route),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete route',
                          onPressed: () => _deleteRoute(route),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _parseColor(String hex) {
    var normalized = hex.replaceFirst('#', '');
    if (normalized.length == 6) normalized = 'FF$normalized';
    return Color(int.parse(normalized, radix: 16));
  }
}
