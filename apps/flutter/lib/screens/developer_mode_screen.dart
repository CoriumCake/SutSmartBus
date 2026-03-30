import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/data_provider.dart';
import '../config/api_config.dart';

class DeveloperModeScreen extends ConsumerStatefulWidget {
  const DeveloperModeScreen({super.key});

  @override
  ConsumerState<DeveloperModeScreen> createState() => _DeveloperModeScreenState();
}

class _DeveloperModeScreenState extends ConsumerState<DeveloperModeScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _systemInfo;
  bool _apiHealth = false;

  @override
  void initState() {
    super.initState();
    _checkServerHealth();
  }

  Future<void> _checkServerHealth() async {
    setState(() => _isLoading = true);
    final api = ref.read(apiServiceProvider);
    
    final health = await api.checkHealth();
    final info = await api.fetchSystemInfo();

    if (mounted) {
      setState(() {
        _apiHealth = health;
        _systemInfo = info;
        _isLoading = false;
      });
    }
  }

  Future<void> _importWaypoints() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final jsonData = json.decode(content);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Route File Parsed'),
            content: SingleChildScrollView(
              child: Text(const JsonEncoder.withIndent('  ').convert(jsonData)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _uploadRoute(jsonData);
                },
                child: const Text('Import to Server'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read file: $e')),
        );
      }
    }
  }

  Future<void> _uploadRoute(Map<String, dynamic> data) async {
    // Currently, API expects specific format for syncRoute or we do it manually.
    // For this generic demo tool, we will just show a success message or use an endpoint if available.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route data prepared for upload (Check API format)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Security check removed: all users can access Developer Mode
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkServerHealth,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildServerStatusCard(context),
                const SizedBox(height: 16),
                _buildToolsCard(context),
              ],
            ),
    );
  }

  Widget _buildServerStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Server Status', style: theme.textTheme.titleLarge),
              ],
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                _apiHealth ? Icons.check_circle : Icons.error,
                color: _apiHealth ? Colors.green : Colors.red,
              ),
              title: const Text('API / App Server'),
              subtitle: Text(ApiConfig.baseUrl),
              trailing: Text(_apiHealth ? 'ONLINE' : 'OFFLINE', 
                style: TextStyle(color: _apiHealth ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.hub, color: Colors.blue),
              title: const Text('MQTT Broker Target'),
              subtitle: Text(ApiConfig.mqttWsUrl),
            ),
            if (_systemInfo != null) ...[
              const Divider(),
              const Text('Node Diagnostics', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('CPU Usage: ${_systemInfo!['cpu_usage'] ?? 'N/A'}'),
              Text('Memory Usage: ${_systemInfo!['memory_usage'] ?? 'N/A'}'),
              Text('Uptime: ${_systemInfo!['uptime'] ?? 'N/A'}'),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildToolsCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
              children: [
                Icon(Icons.build_circle, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Text('Developer Tools', style: theme.textTheme.titleLarge),
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Import Waypoint File'),
              subtitle: const Text('Select a local .json file to define bus routes.'),
              trailing: ElevatedButton(
                onPressed: _importWaypoints,
                child: const Text('Import'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
