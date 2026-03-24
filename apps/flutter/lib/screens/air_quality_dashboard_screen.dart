import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_provider.dart';
import '../models/bus.dart';
import '../utils/air_quality_utils.dart';
import '../widgets/air_quality_map.dart';

class AirQualityDashboardScreen extends ConsumerStatefulWidget {
  const AirQualityDashboardScreen({super.key});

  @override
  ConsumerState<AirQualityDashboardScreen> createState() => _AirQualityDashboardScreenState();
}

class _AirQualityDashboardScreenState extends ConsumerState<AirQualityDashboardScreen> {
  String _timeRange = '1h';
  List<Map<String, dynamic>> _heatmapData = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    // setState(() => _loading = true); // Removed unused _loading variable
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.fetchHeatmapData(timeRange: _timeRange);
      if (mounted) {
        setState(() {
          _heatmapData = data;
          // _loading = false; // Removed unused _loading variable
        });
      }
    } catch (e) {
      // if (mounted) setState(() => _loading = false); // Removed unused _loading variable
      // Error handling can be added here if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final theme = Theme.of(context);

    // Compute stats
    double avgPm = 0;
    if (_heatmapData.isNotEmpty) {
      final validPoints = _heatmapData.where((p) => (p['pm2_5'] ?? p['weight'] ?? 0) > 0).toList();
      if (validPoints.isNotEmpty) {
        avgPm = validPoints.map((p) => (p['pm2_5'] ?? p['weight'] ?? 0) as num).reduce((a, b) => a + b) / validPoints.length;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AQI Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 1. Top Stats Row
            _buildStatsHeader(avgPm),

            const SizedBox(height: 24),

            // 2. Mini Map Preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Regional Heatmap', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 250,
                      child: AirQualityMapWidget(
                        buses: buses,
                        timeRange: _timeRange,
                        onTimeRangeChanged: (val) {
                          setState(() => _timeRange = val);
                          _fetchData();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 3. Trends / Distribution
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pollution Distribution', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 16),
                      _buildTrendBar('Good (0-15)', 0.6, Colors.green),
                      _buildTrendBar('Moderate (15-35)', 0.3, Colors.yellow[700]!),
                      _buildTrendBar('Unhealthy (35+)', 0.1, Colors.red),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 4. Detailed Ranking
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Device Reporting Status', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            ...buses.map((bus) => _buildBusAqiTile(bus)),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader(double avgPm) {
    final theme = Theme.of(context);
    final status = getAirQualityStatus(avgPm);
    final color = getPMColor(avgPm);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text('Average PM2.5', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            avgPm.toStringAsFixed(1),
            style: theme.textTheme.displayLarge?.copyWith(color: color, fontSize: 48),
          ),
          Text(
            status.label.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendBar(String label, double percent, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text('${(percent * 100).round()}%', style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: color.withValues(alpha: 0.1),
              color: color,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusAqiTile(Bus bus) {
    final pm = bus.pm25 ?? 0.0;
    final color = getPMColor(pm);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(Icons.sensors, color: color),
        ),
        title: Text(bus.busName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Last update: ${bus.isOffline ? "Offline" : "Just now"}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              pm.toStringAsFixed(1),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Text('µg/m³', style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
