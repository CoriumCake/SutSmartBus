# 08 — Air Quality Screen Migration

## Purpose
Migrate the Air Quality screen (`AirQualityScreen.js`, 588 lines) — a hybrid view with a PM2.5 heatmap on a map (top half) and live bus air quality cards (bottom half).

## Source Files
- `screens/AirQualityScreen.js` → `lib/screens/air_quality_screen.dart`
- `components/AirQualityMap.js` (375 lines) → `lib/widgets/air_quality_map.dart`
- `utils/airQuality.js` → `lib/utils/air_quality_utils.dart`

---

## Current Behavior

1. **Top half**: Google Map with colored grid overlay (PM2.5 heatmap via colored `Polygon` tiles)
2. **Time filter buttons**: "1h", "24h" filter for heatmap data
3. **Bottom half**: Scrollable list of "Live Bus Air Quality" cards, each showing:
   - Bus name + AQ status badge (Good/Moderate/Unhealthy)
   - PM2.5 + PM10 values
   - Temp + Humidity values
   - Offline indicator
4. **Debug mode**: FAB to spawn a fake bus that paints PM trails on drag
5. Tapping a bus card zooms the map to that bus

---

## Flutter Implementation

### `lib/utils/air_quality_utils.dart`

```dart
import 'package:flutter/material.dart';

class AirQualityStatus {
  final String label;
  final Color color;
  final Color solidColor;

  const AirQualityStatus({
    required this.label,
    required this.color,
    required this.solidColor,
  });
}

AirQualityStatus getAirQualityStatus(double? value) {
  if (value == null) {
    return const AirQualityStatus(
      label: 'No Data', color: Colors.grey, solidColor: Colors.grey,
    );
  }
  if (value <= 25) {
    return AirQualityStatus(
      label: 'Good',
      color: Colors.green.withOpacity(0.4),
      solidColor: Colors.green,
    );
  }
  if (value <= 50) {
    return AirQualityStatus(
      label: 'Moderate',
      color: Colors.yellow.withOpacity(0.4),
      solidColor: const Color(0xFFCCCC00),
    );
  }
  if (value <= 75) {
    return AirQualityStatus(
      label: 'Unhealthy (Sensitive)',
      color: Colors.orange.withOpacity(0.4),
      solidColor: Colors.orange,
    );
  }
  return AirQualityStatus(
    label: 'Unhealthy',
    color: Colors.red.withOpacity(0.4),
    solidColor: Colors.red,
  );
}

Color getPMColor(double pm25) {
  if (pm25 <= 12) return const Color(0xFF4CAF50);   // Green
  if (pm25 <= 35) return const Color(0xFFFFEB3B);   // Yellow
  if (pm25 <= 55) return const Color(0xFFFF9800);   // Orange
  if (pm25 <= 150) return const Color(0xFFF44336);  // Red
  return const Color(0xFF9C27B0);                     // Purple
}
```

### `lib/screens/air_quality_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final buses = ref.watch(busesProvider);
    final debugMode = ref.watch(debugProvider).debugMode;
    final theme = Theme.of(context);

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
                  onTimeRangeChanged: (range) => setState(() => _timeRange = range),
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
                  BoxShadow(color: Colors.black.withOpacity(0.1),
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
```

### `lib/widgets/air_quality_map.dart` (heatmap grid)

The AQ map uses colored `Polygon` tiles to create a heatmap. Each grid cell is 0.001° (~111m). The data comes from the API endpoint `/api/pm/heatmap?range=1h`.

```dart
// Key logic: Fetch heatmap data, merge with live bus positions,
// cluster adjacent cells, and render as colored Polygons.
// See AirQualityMap.js lines 124-220 for the exact clustering algorithm.
// Port the same grid_size (0.001), snap function, and cluster merging.
```

---

## Verification Checklist

- [ ] Map renders with colored polygon tiles for PM2.5 data
- [ ] Time filter buttons ("1h", "24h") switch heatmap data
- [ ] Bottom card list shows all buses with AQ status
- [ ] Status badge colors match: Green (Good), Yellow (Moderate), Orange (Unhealthy Sensitive), Red (Unhealthy)
- [ ] Offline buses show with reduced opacity and OFFLINE badge
- [ ] PM2.5, PM10, Temperature, Humidity values display correctly
- [ ] Tapping a card zooms the map to that bus
