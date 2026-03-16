import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../utils/map_utils.dart';
import '../utils/map_styles.dart';

class IncomingBus {
  final Bus bus;
  final String routeName;
  final String routeColor;
  final int distanceM;
  final int etaMinutes;
  final int stopsAway;

  IncomingBus({
    required this.bus,
    required this.routeName,
    required this.routeColor,
    required this.distanceM,
    required this.etaMinutes,
    required this.stopsAway,
  });
}

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
  BitmapDescriptor? _busIcon;

  static const _sutCenter = LatLng(14.8820, 102.0207);
  static const _initialRegion = CameraPosition(
    target: _sutCenter,
    zoom: 15.5,
  );

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadBusIcon();
  }

  Future<void> _loadBusIcon() async {
    _busIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/bus_icon.png',
    );
    if (mounted) setState(() {});
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
      if (mounted) {
        setState(() => _userLocation = position);
        _mapController?.animateCamera(CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ));
      }
    } catch (e) {
      // Ignore
    }
  }

  Set<Marker> _buildBusMarkers(List<Bus> buses) {
    return buses.where((b) => b.currentLat != null && b.currentLon != null).map((bus) {
      return Marker(
        markerId: MarkerId('bus_${bus.busMac}'),
        position: LatLng(bus.currentLat!, bus.currentLon!),
        icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: bus.busName,
          snippet: 'PM2.5: ${bus.pm25?.toStringAsFixed(1) ?? "--"} | '
              'Seats: ${bus.seatsAvailable ?? "--"}',
        ),
        onTap: () => _onBusTap(bus),
      );
    }).toSet();
  }

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

  Set<Polyline> _buildRoutePolylines() {
    if (_activeRoute == null) return {};

    final waypoints = _activeRoute!.waypoints;
    final color = _parseColor(_activeRoute!.routeColor);
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

    if (currentWpIdx > 0) {
      polylines.add(Polyline(
        polylineId: const PolylineId('passed'),
        points: waypoints.sublist(0, currentWpIdx + 1)
            .map((w) => LatLng(w.latitude, w.longitude)).toList(),
        color: color.withOpacity(0.3),
        width: 4,
      ));
    }

    polylines.add(Polyline(
      polylineId: const PolylineId('upcoming'),
      points: waypoints.sublist(currentWpIdx, upcomingWpIdx + 1)
          .map((w) => LatLng(w.latitude, w.longitude)).toList(),
      color: color,
      width: 6,
    ));

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
    final routes = ref.read(routesProvider);
    final route = routes.where((r) => r.routeId == bus.routeId).firstOrNull;
    if (route != null) {
      setState(() {
        _activeRoute = route;
        _ridingBus = bus;
        if (bus.currentLat != null && bus.currentLon != null) {
           _currentStopIndex = calculateBusStopIndex(route, LatLng(bus.currentLat!, bus.currentLon!));
        }
      });
    }
  }

  int calculateBusStopIndex(BusRoute route, LatLng busPosition) {
    final waypoints = route.waypoints;
    if (waypoints.length < 2) return 0;

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

    int passedStops = 0;
    for (int i = 0; i <= closestSegmentIndex; i++) {
      if (waypoints[i].isStop && waypoints[i].stopName != null) {
        passedStops++;
      }
    }
    return passedStops;
  }

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

  List<IncomingBus> calculateIncomingBuses(
    Waypoint nearbyStop,
    List<Bus> buses,
    List<BusRoute> allRoutes,
  ) {
    const avgBusSpeedMs = 25 * 1000 / 3600;
    final incoming = <IncomingBus>[];

    for (final bus in buses) {
      if (bus.currentLat == null || bus.currentLon == null) continue;

      final route = allRoutes.where((r) => r.routeId == bus.routeId).firstOrNull;
      if (route == null) continue;

      final stopIdx = route.waypoints.indexWhere(
        (wp) => wp.isStop && wp.stopName == nearbyStop.stopName,
      );
      if (stopIdx == -1) continue;

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

      if (busSegmentIdx >= stopIdx) continue;

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

  Widget _buildNearbyPanel(List<BusRoute> routes, List<Bus> buses) {
    if (_userLocation == null) return const SizedBox.shrink();

    final allStops = routes.expand((r) => r.stops).toList();
    final nearest = findNearestStop(
      LatLng(_userLocation!.latitude, _userLocation!.longitude),
      allStops
    );

    if (nearest == null || nearest.distance > 500) return const SizedBox.shrink();

    final incoming = calculateIncomingBuses(nearest.stop, buses, routes);

    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nearby: ${nearest.stop.stopName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (incoming.isEmpty)
                const Text('No incoming buses.')
              else
                ...incoming.take(3).map((b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(color: _parseColor(b.routeColor), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${b.routeName} (${b.bus.busName})')),
                      Text('${b.etaMinutes} min', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final routes = ref.watch(routesProvider);
    final isDark = ref.watch(themeProvider).isDark;

    return Scaffold(
      body: Stack(
        children: [
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
          _buildNearbyPanel(routes, buses),
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
