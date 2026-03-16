# 06 — Map Screen Migration

## Purpose
Migrate the most complex screen (`MapScreen.js`, ~3035 lines) to Flutter. This covers the interactive campus map, bus markers, route polylines, user location, stop markers, proximity boarding, and debug overlays.

## Source File
- `screens/MapScreen.js` (3035 lines) → `lib/screens/map_screen.dart` + multiple widgets

---

## Feature Breakdown

The React Native MapScreen contains these major features that must each be ported:

| Feature | RN Lines (approx) | Flutter Widget/File |
|---|---|---|
| Google Maps rendering | 666-688 | `google_maps_flutter` (built-in) |
| User location + GPS | 714-716 | `geolocator` package |
| Bus markers (animated) | Components | `lib/widgets/bus_marker.dart` |
| Route polylines (3-segment: passed/upcoming/distant) | 376-422 | Polyline with color segments |
| Stop markers (with loop detection) | 427-520 | `lib/widgets/stop_marker.dart` |
| Bus-to-stop index tracking | 210-280 | Logic inside `MapScreenState` |
| "Nearby stop" + "Incoming buses" panel | 557-652 | `lib/widgets/nearby_stop_panel.dart` |
| Proximity-based auto-boarding | 344-359 | Logic in screen state |
| Route simulation (debug) | 319-327 | Debug animation logic |
| Fake bus (debug) | 95-150 | Debug state |
| Map style (light/dark) | 51 | `mapStyles.dart` port |
| Grid overlay (debug) | Component | `lib/widgets/grid_overlay.dart` |

---

## Recommended File Split

Instead of one 3000-line file, split into:

```
lib/screens/map_screen.dart            # Main screen (orchestrator)
lib/widgets/bus_marker.dart            # Animated bus icon marker
lib/widgets/stop_marker.dart           # Bus stop markers
lib/widgets/nearby_stop_panel.dart     # Bottom panel with incoming buses
lib/widgets/route_polyline.dart        # 3-segment route rendering
lib/widgets/map_debug_controls.dart    # Debug panel (simulation, fake bus)
```

---

## Core Implementation

### `lib/screens/map_screen.dart` (skeleton)

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/debug_provider.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../utils/map_utils.dart';
import '../utils/map_styles.dart';
import '../widgets/bus_marker.dart';
import '../widgets/stop_marker.dart';
import '../widgets/nearby_stop_panel.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  Position? _userLocation;
  BusRoute? _activeRoute;
  Bus? _ridingBus;
  int _currentStopIndex = 0;

  // SUT University center coordinates
  static const _sutCenter = LatLng(14.8820, 102.0207);
  static const _initialRegion = CameraPosition(
    target: _sutCenter,
    zoom: 15.5,
  );

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _userLocation = position);

      _mapController?.animateCamera(CameraUpdate.newLatLng(
        LatLng(position.latitude, position.longitude),
      ));
    } catch (e) {
      print('[MapScreen] Error getting location: $e');
    }
  }

  /// Build bus markers from live data
  Set<Marker> _buildBusMarkers(List<Bus> buses) {
    return buses.where((b) => b.currentLat != null && b.currentLon != null).map((bus) {
      return Marker(
        markerId: MarkerId('bus_${bus.busMac}'),
        position: LatLng(bus.currentLat!, bus.currentLon!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: bus.busName,
          snippet: 'PM2.5: ${bus.pm25?.toStringAsFixed(1) ?? "--"} | '
              'Seats: ${bus.seatsAvailable ?? "--"}',
        ),
        onTap: () => _onBusTap(bus),
      );
    }).toSet();
  }

  /// Build stop markers for the active route
  Set<Marker> _buildStopMarkers() {
    if (_activeRoute == null) return {};

    final stops = _activeRoute!.stops;
    return stops.asMap().entries.map((entry) {
      final i = entry.key;
      final stop = entry.value;
      final isPassed = i < _currentStopIndex;
      final isNext = i == _currentStopIndex;

      return Marker(
        markerId: MarkerId('stop_$i'),
        position: LatLng(stop.latitude, stop.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isPassed ? BitmapDescriptor.hueRed
              : isNext ? BitmapDescriptor.hueGreen
              : BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(title: stop.stopName ?? 'Stop ${i + 1}'),
      );
    }).toSet();
  }

  /// Build route polylines (3 segments: passed, upcoming, distant)
  Set<Polyline> _buildRoutePolylines() {
    if (_activeRoute == null) return {};

    final waypoints = _activeRoute!.waypoints;
    final color = _parseColor(_activeRoute!.routeColor);
    final stops = _activeRoute!.stops;

    // Find waypoint indices for stop-based segmentation
    final stopsWithIndices = waypoints
        .asMap()
        .entries
        .where((e) => e.value.isStop && e.value.stopName != null)
        .toList();

    final currentStop = _currentStopIndex > 0 && _currentStopIndex <= stopsWithIndices.length
        ? stopsWithIndices[_currentStopIndex - 1]
        : null;
    final currentWpIdx = currentStop?.key ?? 0;

    final upcomingStopEntry = stopsWithIndices.length > _currentStopIndex + 2
        ? stopsWithIndices[_currentStopIndex + 2]
        : stopsWithIndices.isNotEmpty ? stopsWithIndices.last : null;
    final upcomingWpIdx = upcomingStopEntry?.key ?? waypoints.length - 1;

    final polylines = <Polyline>{};

    // Passed segment (dimmed)
    if (currentWpIdx > 0) {
      polylines.add(Polyline(
        polylineId: const PolylineId('passed'),
        points: waypoints.sublist(0, currentWpIdx + 1)
            .map((w) => LatLng(w.latitude, w.longitude)).toList(),
        color: color.withOpacity(0.3),
        width: 4,
      ));
    }

    // Upcoming segment (bright)
    polylines.add(Polyline(
      polylineId: const PolylineId('upcoming'),
      points: waypoints.sublist(currentWpIdx, upcomingWpIdx + 1)
          .map((w) => LatLng(w.latitude, w.longitude)).toList(),
      color: color,
      width: 6,
    ));

    // Distant segment (very dimmed)
    if (upcomingWpIdx < waypoints.length - 1) {
      polylines.add(Polyline(
        polylineId: const PolylineId('distant'),
        points: waypoints.sublist(upcomingWpIdx)
            .map((w) => LatLng(w.latitude, w.longitude)).toList(),
        color: color.withOpacity(0.15),
        width: 3,
      ));
    }

    return polylines;
  }

  Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  void _onBusTap(Bus bus) {
    // TODO: Load route for this bus, set _activeRoute
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final isDark = ref.watch(themeProvider).isDark;

    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: _initialRegion,
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: {
              ..._buildBusMarkers(buses),
              ..._buildStopMarkers(),
            },
            polylines: _buildRoutePolylines(),
            style: isDark ? darkMapStyleJson : null,
          ),

          // FABs: Locate Me + Refresh
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'locate',
                  onPressed: _getUserLocation,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'refresh',
                  onPressed: () => ref.read(dataProvider.notifier).refreshBuses(),
                  child: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),

          // Nearby stop panel (bottom)
          // NearbyStopPanel(userLocation: _userLocation, ...),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
```

---

## Key Logic Ports

### Bus-to-stop index tracking (lines 210-280 in RN)

The `busBasedStopIndex` logic projects the bus position onto the route path and counts how many stops have been passed. Port this identically:

```dart
int calculateBusStopIndex(BusRoute route, LatLng busPosition) {
  final waypoints = route.waypoints;
  if (waypoints.length < 2) return 0;

  // Find closest segment
  double minDistance = double.infinity;
  int closestSegmentIndex = 0;

  for (int i = 0; i < waypoints.length - 1; i++) {
    final segStart = waypoints[i];
    final segEnd = waypoints[i + 1];

    final dx = segEnd.latitude - segStart.latitude;
    final dy = segEnd.longitude - segStart.longitude;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) continue;

    final t = ((busPosition.latitude - segStart.latitude) * dx +
        (busPosition.longitude - segStart.longitude) * dy) / lenSq;
    final clampedT = t.clamp(0.0, 1.0);

    final projLat = segStart.latitude + clampedT * dx;
    final projLon = segStart.longitude + clampedT * dy;

    final dLat = busPosition.latitude - projLat;
    final dLon = busPosition.longitude - projLon;
    final dist = dLat * dLat + dLon * dLon;

    if (dist < minDistance) {
      minDistance = dist;
      closestSegmentIndex = i;
    }
  }

  // Count stops before or at current segment
  int passedStops = 0;
  for (int i = 0; i <= closestSegmentIndex; i++) {
    if (waypoints[i].isStop && waypoints[i].stopName != null) {
      passedStops++;
    }
  }
  return passedStops;
}
```

### Nearby Stop Detection (lines 557-578 in RN)

```dart
({Waypoint stop, double distance})? findNearestStop(
  LatLng userLocation,
  List<Waypoint> allStops,
) {
  Waypoint? closest;
  double closestDist = double.infinity;

  for (final stop in allStops) {
    final dist = getDistanceFromLatLonInM(
      userLocation.latitude, userLocation.longitude,
      stop.latitude, stop.longitude,
    );
    if (dist < closestDist) {
      closestDist = dist;
      closest = stop;
    }
  }
  if (closest == null) return null;
  return (stop: closest, distance: closestDist);
}
```

### Incoming Buses ETA (lines 581-652 in RN)

```dart
List<IncomingBus> calculateIncomingBuses(
  Waypoint nearbyStop,
  List<Bus> buses,
  List<BusRoute> allRoutes,
) {
  const avgBusSpeedMs = 25 * 1000 / 3600; // 25 km/h
  final incoming = <IncomingBus>[];

  for (final bus in buses) {
    if (bus.currentLat == null || bus.currentLon == null) continue;

    // Find bus's route
    final route = allRoutes.where((r) =>
      r.routeId == bus.routeId
    ).firstOrNull;
    if (route == null) continue;

    // Check if route stops at this stop (by name)
    final stopIdx = route.waypoints.indexWhere(
      (wp) => wp.isStop && wp.stopName == nearbyStop.stopName,
    );
    if (stopIdx == -1) continue;

    // Find bus position on route
    int busSegmentIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < route.waypoints.length - 1; i++) {
      final wp = route.waypoints[i];
      final dist = getDistanceFromLatLonInM(
        bus.currentLat!, bus.currentLon!, wp.latitude, wp.longitude,
      );
      if (dist < minDist) {
        minDist = dist;
        busSegmentIdx = i;
      }
    }

    // Only include if bus is BEFORE the stop
    if (busSegmentIdx >= stopIdx) continue;

    // Calculate distance along route
    double routeDistance = 0;
    for (int i = busSegmentIdx; i < stopIdx; i++) {
      routeDistance += getDistanceFromLatLonInM(
        route.waypoints[i].latitude, route.waypoints[i].longitude,
        route.waypoints[i + 1].latitude, route.waypoints[i + 1].longitude,
      );
    }

    final etaMinutes = (routeDistance / avgBusSpeedMs / 60).round().clamp(1, 999);
    incoming.add(IncomingBus(
      bus: bus,
      routeName: route.routeName,
      routeColor: route.routeColor,
      distanceM: routeDistance.round(),
      etaMinutes: etaMinutes,
      stopsAway: stopIdx - busSegmentIdx,
    ));
  }

  incoming.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
  return incoming;
}
```

---

## Custom Bus Marker Icon

Load the bus icon asset as a `BitmapDescriptor`:

```dart
Future<BitmapDescriptor> _loadBusIcon() async {
  return BitmapDescriptor.asset(
    const ImageConfiguration(size: Size(48, 48)),
    'assets/images/bus_icon.png',
  );
}
```

---

## Verification Checklist

- [ ] Google Map renders centered on SUT campus (14.8820, 102.0207)
- [ ] User location blue dot appears on the map
- [ ] Bus markers appear with bus icon and update positions in real-time
- [ ] Tapping a bus shows its info (name, PM2.5, seats)
- [ ] When a route is active, 3-segment polyline renders (passed=dim, upcoming=bright, distant=very dim)
- [ ] Stop markers render with correct labels
- [ ] Nearby stop panel shows at the bottom
- [ ] Incoming buses list with ETA renders correctly
- [ ] "Locate Me" FAB centers on user location
- [ ] Dark mode switches map style
- [ ] Stop index calculation tracks bus progress along route
