import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TestingScreen extends ConsumerWidget {
  const TestingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Testing & Debug Tools'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildDebugSection(
            context,
            'Fake Bus Simulation',
            [
              ListTile(
                title: const Text('Simulate Bus Movement'),
                subtitle: const Text('Start/Stop a fake bus for testing map updates.'),
                trailing: Switch(
                  value: false, // TODO: Implement actual state
                  onChanged: (value) {
                    // TODO: Implement fake bus simulation logic
                  },
                ),
              ),
              // Add more fake bus controls here
            ],
          ),
          _buildDebugSection(
            context,
            'Server Connection Status',
            [
              ListTile(
                title: const Text('API Connection'),
                subtitle: const Text('Status: Connected'), // TODO: Implement actual status check
                leading: const Icon(Icons.cloud_done),
              ),
              ListTile(
                title: const Text('MQTT Connection'),
                subtitle: const Text('Status: Connected'), // TODO: Implement actual status check
                leading: const Icon(Icons.wifi),
              ),
            ],
          ),
          _buildDebugSection(
            context,
            'MQTT Message Inspector',
            [
              ListTile(
                title: const Text('Last Received Message'),
                subtitle: const Text('Topic: N/A, Payload: N/A'), // TODO: Implement MQTT message logging
                leading: const Icon(Icons.message),
              ),
              // Button to clear logs, etc.
            ],
          ),
          _buildDebugSection(
            context,
            'Route Sync Tools',
            [
              ListTile(
                title: const Text('Force Route Sync'),
                subtitle: const Text('Manually trigger route data synchronization.'),
                trailing: IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () {
                    // TODO: Implement route sync logic
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDebugSection(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}
