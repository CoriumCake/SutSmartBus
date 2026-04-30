import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/bus_service.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/test_mode_provider.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../utils/map_utils.dart';
import '../utils/route_helpers.dart';
import '../providers/simulation_provider.dart';
import '../widgets/bus_card.dart';

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
  final MapController _mapController = MapController();
  Position? _userLocation;
  BusRoute? _activeRoute;
  int _currentStopIndex = 0;
  final BusService _busService = BusService();
  StreamSubscription<Position>? _positionStream;

  static const _sutCenter = LatLng(14.8820, 102.0207);

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    // Get current position once for initial view
    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _userLocation = position);
        _mapController.move(
            LatLng(position.latitude, position.longitude), 15.5);
      }
    } catch (_) {}

    // Start listening for updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (mounted) {
        if (!ref.read(testModeProvider).enabled) {
          setState(() => _userLocation = position);
        }
      }
    });
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  List<Marker> _buildBusMarkers(List<Bus> buses) {
    return buses
        .where((b) => b.currentLat != null && b.currentLon != null)
        .map((bus) {
      final color = _parseColor(bus.routeId != null
          ? ref
              .read(routesProvider)
              .firstWhere((r) => r.routeId == bus.routeId,
                  orElse: () =>
                      BusRoute(routeId: '', routeName: '', waypoints: []))
              .routeColor
          : '#FF9800');

      return Marker(
        point: LatLng(bus.currentLat!, bus.currentLon!),
        width: 100,
        height: 55,
        child: GestureDetector(
          onTap: () => _onBusTap(bus),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4)),
              ],
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.directions_bus,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        bus.busName.split('-').last,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Passenger: ${bus.personCount ?? 0}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildStopMarkers(List<BusRoute> allRoutes) {
    final routesToShow = _activeRoute != null ? [_activeRoute!] : allRoutes;

    return routesToShow.expand((route) {
      return route.stops.asMap().entries.map((entry) {
        final i = entry.key;
        final stop = entry.value;
        final isNext = _activeRoute != null &&
            route.routeId == _activeRoute!.routeId &&
            i == _currentStopIndex;

        return Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: 12,
          height: 12,
          child: Container(
            decoration: BoxDecoration(
              color: isNext ? Colors.green : Colors.white,
              shape: BoxShape.circle,
              border:
                  Border.all(color: _parseColor(route.routeColor), width: 2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    spreadRadius: 1),
              ],
            ),
          ),
        );
      });
    }).toList();
  }

  List<Polyline> _buildRoutePolylines(List<BusRoute> allRoutes) {
    final routesToShow = _activeRoute != null ? [_activeRoute!] : allRoutes;

    return routesToShow.map((route) {
      final color = _parseColor(route.routeColor);
      return Polyline(
        points: route.waypoints
            .map((w) => LatLng(w.latitude, w.longitude))
            .toList(),
        color: color,
        strokeWidth: 5,
        borderStrokeWidth: 2,
        borderColor: Colors.white.withValues(alpha: 0.8),
      );
    }).toList();
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF2563EB);
    try {
      String cleanHex = hex.replaceFirst('#', '');
      if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';
      return Color(int.parse(cleanHex, radix: 16));
    } catch (_) {
      return const Color(0xFF2563EB); // Default blue
    }
  }

  void _onBusTap(Bus bus) {
    final routes = ref.read(routesProvider);
    final route = routes.where((r) => r.routeId == bus.routeId).firstOrNull;
    setState(() {
      _activeRoute = route;
      if (bus.currentLat != null && bus.currentLon != null && route != null) {
        _currentStopIndex = calculateBusStopIndex(
            route, LatLng(bus.currentLat!, bus.currentLon!));
      }
    });
    _mapController.move(LatLng(bus.currentLat!, bus.currentLon!), 16.5);

    // Show bottom sheet with bus details
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) {
        final nextStop = route != null
            ? findNextStop(bus.currentLat, bus.currentLon, route.waypoints)
            : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
          child: BusCard(
            bus: bus,
            routeInfo: route != null
                ? BusRouteInfo(route: route, nextStop: nextStop)
                : null,
            passengerCount: bus.personCount ?? 0,
            onTap: () {
              // Usually clicking the card itself doesn't do anything when it's already a bottom sheet,
              // but we might want to pop it or show more info. We'll do nothing here as ringing handles itself.
            },
            onRingBell: () async {
              try {
                await _busService.ringBell(bus.busMac);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ring signal sent!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to send ring: ${e.toString()}')),
                  );
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        );
      },
    );
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
      final dy = segEnd.longitude - segStart.longitude; // Corrected line
      final lenSq = dx * dx + dy * dy;
      if (lenSq == 0) continue;
      final t = ((busPosition.latitude - segStart.latitude) * dx +
              (busPosition.longitude - segStart.longitude) * dy) /
          lenSq;
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
      if (waypoints[i].isStop && waypoints[i].stopName != null) passedStops++;
    }
    return passedStops;
  }

  Widget _buildNearbyPanel(List<BusRoute> routes, List<Bus> buses) {
    if (_userLocation == null) return const SizedBox.shrink();

    final allStops = routes.expand((r) => r.stops).toList();
    final nearest = findNearestStop(
        LatLng(_userLocation!.latitude, _userLocation!.longitude), allStops);

    if (nearest == null || nearest.distance > 800)
      return const SizedBox.shrink();

    final incoming = calculateIncomingBuses(nearest.stop, buses, routes);

    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.blue, size: 18),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                nearest.stop.stopName ?? 'Nearby Stop',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2D3748),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Nearby Station',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions_walk,
                                size: 16, color: Color(0xFF48BB78)),
                            const SizedBox(width: 4),
                            Text(
                              '${nearest.distance.round()}m',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF48BB78),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Distance',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFA0AEC0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Middle Section
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFEDF2F7)),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // NEXT BUS
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NEXT BUS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0AEC0),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            incoming.isNotEmpty
                                ? incoming.first.bus.busName
                                : '-',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                        width: 1, height: 32, color: const Color(0xFFE2E8F0)),

                    // PASSENGERS
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'PASSENGERS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0AEC0),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            incoming.isNotEmpty
                                ? '${incoming.first.bus.personCount ?? 0}/33'
                                : '-',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                        width: 1, height: 32, color: const Color(0xFFE2E8F0)),

                    // ETA
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'ETA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0AEC0),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            incoming.isNotEmpty
                                ? '${incoming.first.etaMinutes} min'
                                : '-',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748),
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Button
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: incoming.isNotEmpty
                      ? () async {
                          try {
                            await _busService
                                .ringBell(incoming.first.bus.busMac);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Ring signal sent!')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Failed to send ring: ${e.toString()}')),
                              );
                            }
                          }
                        }
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('No incoming buses to ring.')),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFF6C852), // Yellow color from image
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'RING BELL',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({Waypoint stop, double distance})? findNearestStop(
      LatLng userLocation, List<Waypoint> allStops) {
    Waypoint? closest;
    double closestDist = double.infinity;
    for (final stop in allStops) {
      final dist = getDistanceFromLatLonInM(userLocation.latitude,
          userLocation.longitude, stop.latitude, stop.longitude);
      if (dist < closestDist) {
        closestDist = dist;
        closest = stop;
      }
    }
    if (closest == null) return null;
    return (stop: closest, distance: closestDist);
  }

  List<IncomingBus> calculateIncomingBuses(
      Waypoint nearbyStop, List<Bus> buses, List<BusRoute> allRoutes) {
    const avgBusSpeedMs = 25 * 1000 / 3600;
    final incoming = <IncomingBus>[];
    for (final bus in buses) {
      if (bus.currentLat == null || bus.currentLon == null) continue;
      final route =
          allRoutes.where((r) => r.routeId == bus.routeId).firstOrNull;
      if (route == null) continue;
      final stopIdx = route.waypoints
          .indexWhere((wp) => wp.isStop && wp.stopName == nearbyStop.stopName);
      if (stopIdx == -1) continue;
      int busSegmentIdx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < route.waypoints.length - 1; i++) {
        final wp = route.waypoints[i];
        final dist = getDistanceFromLatLonInM(
            bus.currentLat!, bus.currentLon!, wp.latitude, wp.longitude);
        if (dist < minDist) {
          minDist = dist;
          busSegmentIdx = i;
        }
      }
      if (busSegmentIdx >= stopIdx) continue;
      double routeDistance = 0;
      for (int i = busSegmentIdx; i < stopIdx; i++) {
        routeDistance += getDistanceFromLatLonInM(
            route.waypoints[i].latitude,
            route.waypoints[i].longitude,
            route.waypoints[i + 1].latitude,
            route.waypoints[i + 1].longitude);
      }
      final etaMinutes =
          (routeDistance / avgBusSpeedMs / 60).round().clamp(1, 999);
      incoming.add(IncomingBus(
          bus: bus,
          routeName: route.routeName,
          routeColor: route.routeColor,
          distanceM: routeDistance.round(),
          etaMinutes: etaMinutes,
          stopsAway: stopIdx - busSegmentIdx));
    }
    incoming.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return incoming;
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final routes = ref.watch(routesProvider);
    final isDark = ref.watch(themeProvider).isDark;
    final testMode = ref.watch(testModeProvider);

    bool showPanel = false;
    if (_userLocation != null && routes.isNotEmpty) {
      final allStops = routes.expand((r) => r.stops).toList();
      final nearest = findNearestStop(
          LatLng(_userLocation!.latitude, _userLocation!.longitude), allStops);
      if (nearest != null && nearest.distance <= 800) {
        showPanel = true;
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _sutCenter,
              initialZoom: 15.5,
              onTap: (tapPosition, point) {
                if (testMode.enabled) {
                  ref
                      .read(simulationProvider.notifier)
                      .updateLocation(point.latitude, point.longitude);
                  setState(() {
                    _userLocation = Position(
                      latitude: point.latitude,
                      longitude: point.longitude,
                      timestamp: DateTime.now(),
                      accuracy: 100,
                      altitude: 0,
                      altitudeAccuracy: 0,
                      heading: 0,
                      headingAccuracy: 0,
                      speed: 0,
                      speedAccuracy: 0,
                    );
                  });
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Spoofed User & Test Bus Location!'),
                        duration: Duration(milliseconds: 500)),
                  );
                }
              },
              onLongPress: (tapPosition, point) {
                if (testMode.enabled) {
                  ref
                      .read(simulationProvider.notifier)
                      .updateLocation(point.latitude, point.longitude);
                  setState(() {
                    _userLocation = Position(
                      latitude: point.latitude,
                      longitude: point.longitude,
                      timestamp: DateTime.now(),
                      accuracy: 100,
                      altitude: 0,
                      altitudeAccuracy: 0,
                      heading: 0,
                      headingAccuracy: 0,
                      speed: 0,
                      speedAccuracy: 0,
                    );
                  });
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Spoofed User & Test Bus Location!'),
                        duration: Duration(milliseconds: 500)),
                  );
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: isDark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.catcode.sut_smart_bus',
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              PolylineLayer(polylines: _buildRoutePolylines(routes)),
              MarkerLayer(markers: [
                if (_userLocation != null)
                  Marker(
                    point: LatLng(
                        _userLocation!.latitude, _userLocation!.longitude),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                          color: testMode.enabled
                              ? Colors.deepPurple.withValues(alpha: 0.2)
                              : Colors.blue.withValues(alpha: 0.2),
                          shape: BoxShape.circle),
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                              color: testMode.enabled
                                  ? Colors.deepPurple
                                  : Colors.blue,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2)),
                        ),
                      ),
                    ),
                  ),
                ..._buildStopMarkers(routes),
                ..._buildBusMarkers(buses),
              ]),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildModernActionBtn(
                      testMode.enabled
                          ? Icons.bug_report
                          : Icons.bug_report_outlined,
                      () {
                        final wasEnabled = testMode.enabled;
                        ref.read(testModeProvider.notifier).toggle(
                              initialLat: _userLocation?.latitude,
                              initialLon: _userLocation?.longitude,
                            );

                        // Auto-zoom to simulation start
                        if (!wasEnabled && _userLocation != null) {
                          _mapController.move(
                            LatLng(_userLocation!.latitude,
                                _userLocation!.longitude),
                            17.0,
                          );
                        }
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(wasEnabled
                                ? 'Test Mode Disabled: Simulation stopped'
                                : 'Test Mode Enabled: Fake bus spawned at your location'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      color: testMode.enabled ? Colors.orange : null,
                    ),
                  ],
                ),
                _buildModernActionBtn(
                  Icons.bar_chart_rounded,
                  () => context.pushNamed('passengerStats'),
                  color: const Color(0xFF0F766E),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: showPanel ? 230 : 32,
            child: _buildModernActionBtn(Icons.my_location, () {
              if (_userLocation != null) {
                _mapController.move(
                    LatLng(_userLocation!.latitude, _userLocation!.longitude),
                    17.0);
              } else {
                _initLocation();
              }
            }),
          ),
          _buildNearbyPanel(routes, buses),
        ],
      ),
    );
  }

  Widget _buildModernActionBtn(IconData icon, VoidCallback onTap,
      {Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, size: 24, color: color)),
        ),
      ),
    );
  }
}
