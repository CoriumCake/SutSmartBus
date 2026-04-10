import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_provider.dart';
import '../providers/debug_provider.dart';
import '../models/bus.dart';
import '../utils/air_quality_utils.dart';
import '../widgets/air_quality_map.dart';

class AirQualityScreen extends ConsumerStatefulWidget {
  const AirQualityScreen({super.key});

  @override
  ConsumerState<AirQualityScreen> createState() => _AirQualityScreenState();
}

class _AirQualityScreenState extends ConsumerState<AirQualityScreen> {
  String _timeRange = '1h';

  @override
  Widget build(BuildContext context) {
    final List<Bus> buses = ref.watch(busesProvider);
    final bool debugMode = ref.watch(debugProvider).debugMode;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          // Top half: Map with heatmap
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                AirQualityMapWidget(
                  buses: buses,
                  timeRange: _timeRange,
                  onTimeRangeChanged: (String range) => setState(() => _timeRange = range),
                ),
                // Debug FAB
                if (debugMode)
                  Positioned(
                    top: 60, left: 20,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.red,
                      onPressed: () {
                        // Toggle fake bus
                      },
                      child: const Icon(Icons.bug_report, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom half: Live bus air quality cards
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1),
                      offset: const Offset(0, -2), blurRadius: 5),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text('Live Bus Air Quality',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: buses.length,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemBuilder: (context, index) => _buildAQCard(buses[index], theme),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAQCard(Bus bus, ThemeData theme) {
    final aq = getAirQualityStatus(bus.pm25);
    final isOffline = bus.isOffline;

    return Opacity(
      opacity: isOffline ? 0.4 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              // Header: bus name + status badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bus.busName,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      if (isOffline)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: Colors.grey, borderRadius: BorderRadius.circular(15)),
                          child: const Text('OFFLINE',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: Colors.green, borderRadius: BorderRadius.circular(15)),
                          child: const Text('ONLINE',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: aq.solidColor, borderRadius: BorderRadius.circular(15)),
                        child: Text(aq.label,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // PM values
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text.rich(TextSpan(text: 'PM2.5: ', children: [
                    TextSpan(text: bus.pm25?.toStringAsFixed(1) ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' µg/m³'),
                  ])),
                  Text.rich(TextSpan(text: 'PM10: ', children: [
                    TextSpan(text: bus.pm10?.toStringAsFixed(1) ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' µg/m³'),
                  ])),
                ],
              ),
              const SizedBox(height: 5),
              // Temp + Humidity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text.rich(TextSpan(text: 'Temp: ', children: [
                    TextSpan(text: bus.temp?.toStringAsFixed(1) ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' °C'),
                  ])),
                  Text.rich(TextSpan(text: 'Hum: ', children: [
                    TextSpan(text: bus.hum?.toStringAsFixed(0) ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' %'),
                  ])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
