import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_provider.dart';
import '../config/api_config.dart';

class DeveloperModeScreen extends ConsumerStatefulWidget {
  const DeveloperModeScreen({super.key});

  @override
  ConsumerState<DeveloperModeScreen> createState() =>
      _DeveloperModeScreenState();
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
                  style: TextStyle(
                      color: _apiHealth ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.hub, color: Colors.blue),
              title: const Text('MQTT Broker Target'),
              subtitle: Text(ApiConfig.mqttWsUrl),
            ),
            if (_systemInfo != null) ...[
              const Divider(),
              const Text('Node Diagnostics',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
}
