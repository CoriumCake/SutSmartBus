import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/simulation_provider.dart';
import '../providers/data_provider.dart';
import '../providers/test_mode_provider.dart';

class TestingScreen extends ConsumerStatefulWidget {
  const TestingScreen({super.key});

  @override
  ConsumerState<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends ConsumerState<TestingScreen> {
  String _lastDetection = 'Waiting for data...';
  
  @override
  void initState() {
    super.initState();
    _listenToDetection();
  }
  
  void _listenToDetection() {
    final mqtt = ref.read(mqttServiceProvider);
    mqtt.onMessage = (topic, message) {
      if (topic == 'sut/person-detection') {
        if (mounted) {
           setState(() {
             _lastDetection = 'Total Users: ${message['total_unique_persons'] ?? 0}\nEntering: ${message['entering'] ?? 0}\nExiting: ${message['exiting'] ?? 0}\nProcessing Time: ${message['processing_time_ms'] ?? 0}ms';
           });
        }
      }
      // Re-route normal messages to data provider
      ref.read(dataProvider.notifier).handleMqttMessage(topic, message);
    };
  }

  @override
  Widget build(BuildContext context) {
    final sim = ref.watch(simulationProvider);
    final data = ref.watch(dataProvider);

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
                subtitle: Text(sim.isSimulating ? 'Sending fake GPS/PM data...' : 'Inactive'),
                trailing: Switch(
                  value: sim.isSimulating,
                  onChanged: (value) {
                    ref.read(simulationProvider.notifier).toggleSimulation(value);
                  },
                ),
              ),
            ],
          ),
          _buildDebugSection(
            context,
            'Server Connection Status',
            [
              ListTile(
                title: const Text('Data Layer Status'),
                subtitle: Text(data.loading ? 'Loading...' : (data.error != null ? 'Error: ${data.error}' : 'Connected')),
                leading: Icon(
                  data.error != null ? Icons.error_outline : Icons.cloud_done,
                  color: data.error != null ? Colors.red : Colors.green,
                ),
              ),
              ListTile(
                title: const Text('Active Buses'),
                subtitle: Text('Buses in memory: ${data.buses.length}'),
                leading: const Icon(Icons.directions_bus),
              ),
            ],
          ),
          _buildDebugSection(
            context,
            'MQTT Message Inspector',
            [
              ListTile(
                title: const Text('Topic Monitoring'),
                subtitle: const Text('Subscribed to: sut/app/bus/location, etc.'),
                leading: const Icon(Icons.message),
              ),
              ListTile(
                title: const Text('ESP32-CAM Counting Data'),
                subtitle: Text(_lastDetection),
                leading: const Icon(Icons.people_alt_outlined),
              ),
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
                    ref.read(dataProvider.notifier).refreshBuses();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing buses...'))
                    );
                  },
                ),
              ),
            ],
          ),
          _buildTestModeSection(context),
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

  // ─── Test Mode (ESP32 Cam) Section ────────────────────────────────────────

  Widget _buildTestModeSection(BuildContext context) {
    final testMode = ref.watch(testModeProvider);
    final notifier = ref.read(testModeProvider.notifier);

    return _buildDebugSection(
      context,
      'Test Mode (ESP32 Cam)',
      [
        // ── Toggle ─────────────────────────────────────────────────────────
        SwitchListTile(
          key: const Key('test_mode_toggle'),
          title: const Text('Enable Test Mode'),
          subtitle: Text(
            testMode.enabled
                ? 'Subscribed to MQTT · Fake bus running'
                : 'Disabled – no MQTT subscription active',
          ),
          secondary: Icon(
            testMode.enabled ? Icons.videocam : Icons.videocam_off,
            color: testMode.enabled ? Colors.green : null,
          ),
          value: testMode.enabled,
          onChanged: (_) => notifier.toggle(),
        ),

        if (testMode.enabled) ...[
          const Divider(height: 8),

          // ── Camera URL picker ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              key: const Key('cam_url_dropdown'),
              decoration: const InputDecoration(
                labelText: 'Camera Source',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.camera_alt_outlined),
              ),
              initialValue: testMode.selectedCamUrl,
              items: kCamUrls
                  .map((url) => DropdownMenuItem(
                        value: url,
                        child: Text(
                          url,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ))
                  .toList(),
              onChanged: (url) {
                if (url != null) notifier.selectCam(url);
              },
            ),
          ),

          // ── Person count display ───────────────────────────────────────────
          ListTile(
            key: const Key('person_count_tile'),
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text('People Detected (ESP32-CAM)'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${testMode.simulatedPersonCount}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
          ),

          // ── Simulated position mini-map ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Simulated User Position',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 8),
                _SimulatedPositionMap(
                  key: const Key('sim_position_map'),
                  position: testMode.simulatedUserPosition,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Simulated Position Mini-Map Widget ────────────────────────────────────────

class _SimulatedPositionMap extends StatelessWidget {
  final Offset? position;

  const _SimulatedPositionMap({super.key, this.position});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const mapWidth = 260.0;
    const mapHeight = 160.0;

    return Container(
      width: mapWidth,
      height: mapHeight,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          // Grid hint lines
          CustomPaint(
            size: const Size(mapWidth, mapHeight),
            painter: _GridPainter(
              lineColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          // Position dot
          if (position != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              left: position!.dx - 8,
              top: position!.dy - 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          // Label
          Positioned(
            bottom: 6,
            right: 8,
            child: Text(
              position != null
                  ? '(${position!.dx.toStringAsFixed(0)}, ${position!.dy.toStringAsFixed(0)})'
                  : '–',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color lineColor;
  const _GridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8;
    const step = 40.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.lineColor != lineColor;
}
