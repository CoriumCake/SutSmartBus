# 11 — Utility Functions Migration

## Purpose
Migrate all utility/helper functions from JavaScript to Dart. These are small, pure functions used across multiple screens.

## Source Files
- `utils/mapUtils.js` → `lib/utils/map_utils.dart`
- `utils/routeHelpers.js` → `lib/utils/route_helpers.dart`
- `utils/airQuality.js` → `lib/utils/air_quality_utils.dart` (already done in 08)
- `utils/mapStyles.js` → `lib/utils/map_styles.dart`
- `config/allowed_devices.js` / `DebugContext` allowlist → `lib/config/allowed_devices.dart`

---

## 1. Map Utilities

### `lib/utils/map_utils.dart`

```dart
import 'dart:math';

/// Convert degrees to radians
double deg2rad(double deg) => deg * (pi / 180);

/// Calculate distance between two points in meters (Haversine formula)
double getDistanceFromLatLonInM(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0; // Radius of earth in km
  final dLat = deg2rad(lat2 - lat1);
  final dLon = deg2rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(deg2rad(lat1)) * cos(deg2rad(lat2)) *
      sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c * 1000; // Distance in meters
}

/// Calculate route metrics (total distance + per-segment distances)
({double totalDistance, List<double> segmentDistances}) getRouteMetrics(
    List<({double latitude, double longitude})> waypoints) {
  double totalDistance = 0;
  final segmentDistances = <double>[];

  if (waypoints.length < 2) {
    return (totalDistance: 0, segmentDistances: []);
  }

  for (int i = 0; i < waypoints.length - 1; i++) {
    final d = getDistanceFromLatLonInM(
      waypoints[i].latitude, waypoints[i].longitude,
      waypoints[i + 1].latitude, waypoints[i + 1].longitude,
    );
    totalDistance += d;
    segmentDistances.add(d);
  }

  return (totalDistance: totalDistance, segmentDistances: segmentDistances);
}

/// Douglas-Peucker polyline simplification
/// Reduces points while preserving shape. Tolerance in degrees.
double _perpendicularDistance(
    ({double latitude, double longitude}) point,
    ({double latitude, double longitude}) lineStart,
    ({double latitude, double longitude}) lineEnd,
) {
  final dx = lineEnd.longitude - lineStart.longitude;
  final dy = lineEnd.latitude - lineStart.latitude;
  final mag = sqrt(dx * dx + dy * dy);
  if (mag == 0) return 0;

  final u = ((point.longitude - lineStart.longitude) * dx +
      (point.latitude - lineStart.latitude) * dy) / (mag * mag);
  final closestX = lineStart.longitude + u * dx;
  final closestY = lineStart.latitude + u * dy;

  return sqrt(pow(point.longitude - closestX, 2) + pow(point.latitude - closestY, 2));
}

List<({double latitude, double longitude})> simplifyPolyline(
    List<({double latitude, double longitude})> points,
    {double tolerance = 0.00003}) {
  if (points.length < 3) return points;

  double maxDist = 0;
  int maxIdx = 0;

  for (int i = 1; i < points.length - 1; i++) {
    final dist = _perpendicularDistance(points[i], points.first, points.last);
    if (dist > maxDist) {
      maxDist = dist;
      maxIdx = i;
    }
  }

  if (maxDist > tolerance) {
    final left = simplifyPolyline(points.sublist(0, maxIdx + 1), tolerance: tolerance);
    final right = simplifyPolyline(points.sublist(maxIdx), tolerance: tolerance);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  return [points.first, points.last];
}
```

---

## 2. Route Helpers

### `lib/utils/route_helpers.dart`

```dart
import 'dart:math';
import '../models/waypoint.dart';
import 'map_utils.dart';

/// Result of finding the next stop
class NextStopResult {
  final String stopName;
  final int stopIndex;
  final int? distanceM;
  final int? etaMinutes;

  NextStopResult({
    required this.stopName,
    required this.stopIndex,
    this.distanceM,
    this.etaMinutes,
  });
}

/// Find the closest waypoint index to a given position
int findClosestWaypointIndex(double lat, double lon, List<Waypoint> waypoints) {
  if (waypoints.isEmpty) return -1;

  int closestIndex = 0;
  double minDistance = double.infinity;

  for (int i = 0; i < waypoints.length; i++) {
    final wp = waypoints[i];
    final distance = getDistanceFromLatLonInM(lat, lon, wp.latitude, wp.longitude);
    if (distance < minDistance) {
      minDistance = distance;
      closestIndex = i;
    }
  }

  return closestIndex;
}

/// Find the next stop along a route from the bus's current position
/// [averageSpeedMps] = average speed in meters per second (default ~30 km/h = 8.33 m/s)
NextStopResult? findNextStop(
    double? busLat, double? busLon, List<Waypoint> waypoints,
    {double averageSpeedMps = 8.33}) {
  if (waypoints.isEmpty || busLat == null || busLon == null) return null;

  final currentIndex = findClosestWaypointIndex(busLat, busLon, waypoints);

  // Search forward for next stop
  for (int i = currentIndex; i < waypoints.length; i++) {
    final wp = waypoints[i];
    if (wp.isStop) {
      final distance = getDistanceFromLatLonInM(busLat, busLon, wp.latitude, wp.longitude);
      final etaSeconds = distance / averageSpeedMps;
      final etaMinutes = max(1, (etaSeconds / 60).round());

      return NextStopResult(
        stopName: wp.stopName ?? 'Stop ${i + 1}',
        stopIndex: i,
        distanceM: distance.round(),
        etaMinutes: etaMinutes,
      );
    }
  }

  // Wrap around to find first stop (circular route)
  for (int i = 0; i < currentIndex; i++) {
    final wp = waypoints[i];
    if (wp.isStop) {
      return NextStopResult(
        stopName: wp.stopName ?? 'Stop ${i + 1}',
        stopIndex: i,
        distanceM: null, // Unknown for wrapped routes
        etaMinutes: null,
      );
    }
  }

  return null;
}

/// Get all stop waypoints from a route
List<Waypoint> getStopsFromRoute(List<Waypoint> waypoints) {
  return waypoints.where((wp) => wp.isStop).toList();
}
```

---

## 3. Map Styles

### `lib/utils/map_styles.dart`

```dart
/// Google Maps dark style JSON (same as React Native `mapStyles.js`)
const String darkMapStyleJson = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#757575"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#181818"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1a3320"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8a8a8a"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#373737"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3c3c3c"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry", "stylers": [{"color": "#4e4e4e"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "transit", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#3d3d3d"}]}
]
''';

/// Light map style (empty = default Google Maps)
const String lightMapStyleJson = '[]';
```

---

## 4. Allowed Devices Config

### `lib/config/allowed_devices.dart`

```dart
/// Device IDs allowed to access debug features
/// Port the values from the React Native project's DebugContext.js allowlist
const allowedDeviceIds = <String>{
  // Add actual device IDs here
  // e.g., 'RZCW3031X2M' for Samsung Galaxy
};
```

> **Agent Note:** Check the React Native `DebugContext.js` for the actual device ID allowlist and copy those values here.

---

## Verification Checklist

- [ ] `getDistanceFromLatLonInM` returns correct results (test with known coordinates)
- [ ] `simplifyPolyline` reduces points while maintaining shape
- [ ] `findNextStop` locates the correct upcoming stop
- [ ] `findClosestWaypointIndex` returns the closest waypoint to a given position
- [ ] `darkMapStyleJson` compiles as valid JSON
- [ ] All utility functions are pure (no side effects, no dependencies on Flutter)
