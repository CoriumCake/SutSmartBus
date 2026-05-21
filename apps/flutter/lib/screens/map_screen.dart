import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import '../services/bus_service.dart';
import '../providers/data_provider.dart';
import '../providers/developer_settings_provider.dart';
import '../providers/debug_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/test_mode_provider.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../utils/map_utils.dart';
import '../utils/route_helpers.dart';

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

class BusArrivalDetails {
  final NextStopResult? nextStop;
  final Waypoint? targetStop;
  final int? targetWaypointIndex;
  final int etaMinutes;
  final int distanceM;
  final int stopsAway;
  final double walkingDistanceM;

  const BusArrivalDetails({
    required this.nextStop,
    required this.targetStop,
    required this.targetWaypointIndex,
    required this.etaMinutes,
    required this.distanceM,
    required this.stopsAway,
    required this.walkingDistanceM,
  });
}

class _BusHeadingTransform {
  final double angleRadians;
  final bool flipHorizontally;

  const _BusHeadingTransform({
    required this.angleRadians,
    required this.flipHorizontally,
  });
}

Widget _buildOrientedBusIcon(_BusHeadingTransform heading) {
  return Transform.rotate(
    angle: heading.angleRadians,
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        heading.flipHorizontally ? -1.0 : 1.0,
        1.0,
        1.0,
      ),
      child: Image.asset(
        'assets/images/bus_icon.png',
        fit: BoxFit.contain,
      ),
    ),
  );
}

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey _mapViewportKey = GlobalKey();
  final Map<String, LatLng> _renderedBusPositions = {};
  final Map<String, LatLng> _busAnimationStart = {};
  final Map<String, LatLng> _busAnimationTarget = {};
  final Map<String, DateTime> _busAnimationStartedAt = {};
  final Map<String, Duration> _busAnimationTravelDurations = {};
  final Map<String, LatLng> _lastRawBusPositions = {};
  final Map<String, LatLng> _previousRawBusPositions = {};
  final Map<String, DateTime> _lastRawBusUpdatedAt = {};
  final Map<String, DateTime> _previousRawBusUpdatedAt = {};
  final Map<String, Bus> _latestBusesByMac = {};
  final Map<String, int> _lockedNextStopWaypointIndexByBus = {};
  Position? _userLocation;
  BusRoute? _activeRoute;
  String? _activeBusMac;
  String? _selectedInfoBusMac;
  String? _selectedStopKey;
  String? _selectedStopRouteId;
  int? _selectedStopRouteIndex;
  String? _rideReadyBusMac;
  String? _ridingBusMac;
  DateTime? _rideReadySince;
  int _currentStopIndex = 0;
  final BusService _busService = BusService();
  StreamSubscription<Position>? _positionStream;
  Timer? _rideReadyTimer;
  Timer? _busAnimationTimer;
  Timer? _rideSessionMonitorTimer;
  String? _activeRideSessionId;
  bool _isStartingRide = false;
  bool _isRingingBell = false;
  bool _isRingBellAvailable = false;
  String? _noGpsAssignedBusMac;
  LatLng? _lastNoGpsSyncedPoint;
  DateTime? _lastNoGpsSyncedAt;
  bool _isSyncingNoGpsBusLocation = false;

  static const _sutCenter = LatLng(14.8820, 102.0207);
  static const Color _mapAccent = AppTheme.sutOrange;
  static const double _rideDetectionDistanceM = 25;
  static const double _rideDetectionGraceDistanceM = 32;
  static const double _rideGpsAccuracyCompensationCapM = 15;
  static const Duration _rideDetectionDuration = Duration(seconds: 5);
  static const Duration _busAnimationFrame = Duration(milliseconds: 16);
  static const Duration _busAnimationMinDuration = Duration(milliseconds: 900);
  static const Duration _busAnimationMaxDuration = Duration(milliseconds: 2800);
  static const Duration _busMaxExtrapolationDuration =
      Duration(milliseconds: 1800);
  static const double _busMaxExtrapolationDistanceM = 45;
  static const double _busSnapJitterHoldDistanceM = 6;
  static const double _busSnapBlendDistanceM = 18;
  static const double _busSnapBlendFactor = 0.35;
  static const double _nextStopHoldDistanceM = 90;
  static const double _nextStopReleaseDistanceM = 35;
  static const double _stopArrivalDistanceM = 20;
  static const double _selectedBusDockMaxWidth = 420;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _rideReadyTimer?.cancel();
    _busAnimationTimer?.cancel();
    _rideSessionMonitorTimer?.cancel();
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
          _maybeSyncNoGpsAssignedBus(
            buses: ref.read(busesProvider),
            noGpsModeEnabled:
                ref.read(developerSettingsProvider).noGpsModeEnabled,
          );
        }
      }
    });
  }

  Bus? _resolveNoGpsAssignedBus(List<Bus> buses) {
    if (buses.isEmpty) {
      return null;
    }

    final assignedBusMac = ref.read(developerSettingsProvider).assignedBusMac;
    if (assignedBusMac != null && assignedBusMac.isNotEmpty) {
      for (final bus in buses) {
        if (bus.busMac == assignedBusMac) {
          return bus;
        }
      }
    }

    final preferredMac = _ridingBusMac ?? _activeBusMac ?? _selectedInfoBusMac;
    if (preferredMac != null) {
      for (final bus in buses) {
        if (bus.busMac == preferredMac) {
          return bus;
        }
      }
    }

    final onlineBuses = buses.where((bus) => !bus.isOffline).toList();
    if (onlineBuses.length == 1) {
      return onlineBuses.first;
    }

    if (buses.length == 1) {
      return buses.first;
    }

    return null;
  }

  Future<void> _maybeSyncNoGpsAssignedBus({
    required List<Bus> buses,
    required bool noGpsModeEnabled,
  }) async {
    final userLocation = _userLocation;
    if (!noGpsModeEnabled || userLocation == null) {
      _noGpsAssignedBusMac = null;
      _lastNoGpsSyncedPoint = null;
      _lastNoGpsSyncedAt = null;
      return;
    }

    final assignedBus = _resolveNoGpsAssignedBus(buses);
    if (assignedBus == null) {
      return;
    }

    final nextPoint = LatLng(userLocation.latitude, userLocation.longitude);
    final now = DateTime.now();
    final timeSinceLastSync =
        _lastNoGpsSyncedAt == null ? null : now.difference(_lastNoGpsSyncedAt!);
    final movedDistanceM = _lastNoGpsSyncedPoint == null
        ? null
        : getDistanceFromLatLonInM(
            _lastNoGpsSyncedPoint!.latitude,
            _lastNoGpsSyncedPoint!.longitude,
            nextPoint.latitude,
            nextPoint.longitude,
          );
    final busChanged = _noGpsAssignedBusMac != assignedBus.busMac;
    final shouldSync = busChanged ||
        _lastNoGpsSyncedAt == null ||
        (timeSinceLastSync != null && timeSinceLastSync.inSeconds >= 8) ||
        (movedDistanceM != null && movedDistanceM >= 10);

    if (!shouldSync || _isSyncingNoGpsBusLocation) {
      return;
    }

    _isSyncingNoGpsBusLocation = true;
    try {
      await _busService.updateDeveloperBusLocation(
        busMac: assignedBus.busMac,
        lat: nextPoint.latitude,
        lon: nextPoint.longitude,
      );
      ref.read(dataProvider.notifier).updateBusLocally(
            assignedBus.copyWith(
              currentLat: nextPoint.latitude,
              currentLon: nextPoint.longitude,
              isOnline: true,
              lastUpdated: now.millisecondsSinceEpoch,
            ),
          );
      _noGpsAssignedBusMac = assignedBus.busMac;
      _lastNoGpsSyncedPoint = nextPoint;
      _lastNoGpsSyncedAt = now;
    } catch (_) {
      // Best effort sync for developer mode only.
    } finally {
      _isSyncingNoGpsBusLocation = false;
    }
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

  List<Marker> _buildBusMarkers(
    List<Bus> buses,
    List<BusRoute> routes,
  ) {
    return buses
        .where((b) => b.currentLat != null && b.currentLon != null)
        .map((bus) {
      final isActive =
          _activeBusMac == bus.busMac || _ridingBusMac == bus.busMac;
      final heading = _headingTransformForBus(bus, routes);

      final markerChild = GestureDetector(
        onTap: () => _onBusTap(bus),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          scale: isActive ? 1.08 : 1.0,
          child: Opacity(
            opacity: bus.isOffline ? 0.6 : 1.0,
            child: _buildOrientedBusIcon(heading),
          ),
        ),
      );

      return Marker(
        point: LatLng(bus.currentLat!, bus.currentLon!),
        width: isActive ? 42 : 36,
        height: isActive ? 42 : 36,
        child: markerChild,
      );
    }).toList();
  }

  _BusHeadingTransform _headingTransformForBus(Bus bus, List<BusRoute> routes) {
    final currentPoint = _renderedBusPositions[bus.busMac] ??
        (bus.currentLat != null && bus.currentLon != null
            ? LatLng(bus.currentLat!, bus.currentLon!)
            : null);
    final targetPoint = _busAnimationTarget[bus.busMac];
    final previousPoint = _previousRawBusPositions[bus.busMac];
    final latestRawPoint = _lastRawBusPositions[bus.busMac];

    if (currentPoint != null &&
        targetPoint != null &&
        _pointDistanceSquared(currentPoint, targetPoint) > 0) {
      return _headingFromPoints(currentPoint, targetPoint);
    }

    if (previousPoint != null &&
        latestRawPoint != null &&
        _pointDistanceSquared(previousPoint, latestRawPoint) > 0) {
      return _headingFromPoints(previousPoint, latestRawPoint);
    }

    if (bus.currentLat != null && bus.currentLon != null) {
      final route = _resolveRouteForBus(bus, routes);
      if (route != null && route.waypoints.length >= 2) {
        final busPoint = LatLng(bus.currentLat!, bus.currentLon!);
        final segmentIndex = calculateClosestSegmentIndex(route, busPoint);
        final start = route.waypoints[segmentIndex];
        final end = route
            .waypoints[math.min(segmentIndex + 1, route.waypoints.length - 1)];
        final startPoint = LatLng(start.latitude, start.longitude);
        final endPoint = LatLng(end.latitude, end.longitude);
        if (_pointDistanceSquared(startPoint, endPoint) > 0) {
          return _headingFromPoints(startPoint, endPoint);
        }
      }
    }

    return const _BusHeadingTransform(angleRadians: 0, flipHorizontally: false);
  }

  double _pointDistanceSquared(LatLng a, LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLon = a.longitude - b.longitude;
    return (dLat * dLat) + (dLon * dLon);
  }

  _BusHeadingTransform _headingFromPoints(LatLng from, LatLng to) {
    final dx = to.longitude - from.longitude;
    final dy = -(to.latitude - from.latitude);
    final rawAngle = math.atan2(dy, dx);
    final flipHorizontally = rawAngle > math.pi / 2 || rawAngle < -math.pi / 2;
    final normalizedAngle = flipHorizontally
        ? (rawAngle > 0 ? rawAngle - math.pi : rawAngle + math.pi)
        : rawAngle;
    return _BusHeadingTransform(
      angleRadians: normalizedAngle,
      flipHorizontally: flipHorizontally,
    );
  }

  void _syncAnimatedBusPositions(List<Bus> buses, List<BusRoute> routes) {
    final activeBusMacs = buses.map((bus) => bus.busMac).toSet();
    _renderedBusPositions
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _busAnimationStart
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _busAnimationTarget
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _busAnimationStartedAt
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _busAnimationTravelDurations
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _lastRawBusPositions
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _previousRawBusPositions
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _lastRawBusUpdatedAt
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _previousRawBusUpdatedAt
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _latestBusesByMac
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));
    _lockedNextStopWaypointIndexByBus
        .removeWhere((busMac, _) => !activeBusMacs.contains(busMac));

    var hasAnimatingBus = false;

    for (final bus in buses) {
      _latestBusesByMac[bus.busMac] = bus;
      final lat = bus.currentLat;
      final lon = bus.currentLon;
      if (lat == null || lon == null) {
        continue;
      }

      final nextPoint = _smoothedPointForBus(bus, routes) ?? LatLng(lat, lon);
      final currentRendered = _renderedBusPositions[bus.busMac];
      final currentTarget = _busAnimationTarget[bus.busMac];

      if (currentRendered == null) {
        _renderedBusPositions[bus.busMac] = nextPoint;
        _busAnimationStart[bus.busMac] = nextPoint;
        _busAnimationTarget[bus.busMac] = nextPoint;
        _busAnimationStartedAt[bus.busMac] = DateTime.now();
        _busAnimationTravelDurations[bus.busMac] = _busAnimationMinDuration;
        _lastRawBusPositions[bus.busMac] = nextPoint;
        _lastRawBusUpdatedAt[bus.busMac] = DateTime.now();
        continue;
      }

      final lastRaw = _lastRawBusPositions[bus.busMac];
      final hasRawChange = lastRaw == null ||
          lastRaw.latitude != nextPoint.latitude ||
          lastRaw.longitude != nextPoint.longitude;

      if (hasRawChange &&
          (currentTarget == null ||
              currentTarget.latitude != nextPoint.latitude ||
              currentTarget.longitude != nextPoint.longitude)) {
        final now = DateTime.now();
        final previousUpdatedAt = _lastRawBusUpdatedAt[bus.busMac];
        if (lastRaw != null && previousUpdatedAt != null) {
          _previousRawBusPositions[bus.busMac] = lastRaw;
          _previousRawBusUpdatedAt[bus.busMac] = previousUpdatedAt;
        }
        _lastRawBusPositions[bus.busMac] = nextPoint;
        _lastRawBusUpdatedAt[bus.busMac] = now;
        _busAnimationStart[bus.busMac] = currentRendered;
        _busAnimationTarget[bus.busMac] = nextPoint;
        _busAnimationStartedAt[bus.busMac] = now;
        _busAnimationTravelDurations[bus.busMac] = _resolveTravelDuration(
          previousUpdatedAt: previousUpdatedAt,
          updatedAt: now,
        );
        hasAnimatingBus = true;
      } else {
        final startedAt = _busAnimationStartedAt[bus.busMac];
        final travelDuration = _busAnimationTravelDurations[bus.busMac] ??
            _busAnimationMinDuration;
        if (startedAt != null &&
            DateTime.now().difference(startedAt) < travelDuration) {
          hasAnimatingBus = true;
        } else if (_estimateExtrapolatedPoint(bus.busMac, DateTime.now()) !=
            null) {
          hasAnimatingBus = true;
        }
      }
    }

    if (hasAnimatingBus) {
      _ensureBusAnimationTimer();
    } else if (_busAnimationTimer != null) {
      _busAnimationTimer?.cancel();
      _busAnimationTimer = null;
    }
  }

  void _ensureBusAnimationTimer() {
    _busAnimationTimer ??=
        Timer.periodic(_busAnimationFrame, (_) => _tickBusAnimations());
  }

  void _tickBusAnimations() {
    if (!mounted) {
      _busAnimationTimer?.cancel();
      _busAnimationTimer = null;
      return;
    }

    final now = DateTime.now();
    var hasAnimatingBus = false;

    for (final busMac in _busAnimationTarget.keys.toList()) {
      final start = _busAnimationStart[busMac];
      final target = _busAnimationTarget[busMac];
      final startedAt = _busAnimationStartedAt[busMac];

      if (start == null || target == null || startedAt == null) {
        continue;
      }

      final travelDuration =
          _busAnimationTravelDurations[busMac] ?? _busAnimationMinDuration;
      final progress = ((now.difference(startedAt).inMilliseconds) /
              travelDuration.inMilliseconds)
          .clamp(0.0, 1.0);

      if (progress >= 1.0) {
        final extrapolated = _estimateExtrapolatedPoint(busMac, now);
        if (extrapolated != null) {
          hasAnimatingBus = true;
          _renderedBusPositions[busMac] = extrapolated;
        } else {
          _renderedBusPositions[busMac] = target;
          _busAnimationStart[busMac] = target;
        }
      } else {
        hasAnimatingBus = true;
        _renderedBusPositions[busMac] = LatLng(
          _lerpDouble(start.latitude, target.latitude,
              Curves.linear.transform(progress)),
          _lerpDouble(start.longitude, target.longitude,
              Curves.linear.transform(progress)),
        );
      }
    }

    final followBusMac = _ridingBusMac ?? _activeBusMac;
    if (followBusMac != null) {
      final followPoint = _renderedBusPositions[followBusMac];
      if (followPoint != null) {
        _moveCameraToFollowBus(followPoint);
      }
    }

    if (!hasAnimatingBus) {
      _busAnimationTimer?.cancel();
      _busAnimationTimer = null;
    }

    setState(() {});
  }

  double _lerpDouble(double start, double end, double t) {
    return start + ((end - start) * t);
  }

  void _moveCameraToFollowBus(LatLng busPoint, {double? zoom}) {
    final renderObject =
        _mapViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null) {
      _mapController.move(busPoint, zoom ?? _mapController.camera.zoom);
      return;
    }

    final screenSize = renderObject.size;
    final screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final busScreen = _mapController.camera.latLngToScreenPoint(busPoint);
    final desiredBusX = screenCenter.dx;
    final desiredBusY = _selectedInfoBusMac != null
        ? screenSize.height * 0.38
        : _ridingBusMac != null
            ? screenSize.height * 0.56
            : screenCenter.dy;
    final deltaX = desiredBusX - busScreen.x;
    final deltaY = desiredBusY - busScreen.y;
    final targetCenter = _mapController.camera.offsetToCrs(
      Offset(screenCenter.dx - deltaX, screenCenter.dy - deltaY),
    );

    _mapController.move(targetCenter, zoom ?? _mapController.camera.zoom);
  }

  void _clearSelectedBusFocus() {
    if (_ridingBusMac != null) {
      setState(() {
        _selectedInfoBusMac = null;
        _selectedStopKey = null;
        _selectedStopRouteId = null;
        _selectedStopRouteIndex = null;
      });
      return;
    }

    setState(() {
      _selectedInfoBusMac = null;
      _selectedStopKey = null;
      _selectedStopRouteId = null;
      _selectedStopRouteIndex = null;
      _activeBusMac = null;
      _activeRoute = null;
    });
  }

  Duration _resolveTravelDuration({
    required DateTime? previousUpdatedAt,
    required DateTime updatedAt,
  }) {
    if (previousUpdatedAt == null) {
      return _busAnimationMinDuration;
    }

    final rawInterval = updatedAt.difference(previousUpdatedAt);
    if (rawInterval <= Duration.zero) {
      return _busAnimationMinDuration;
    }

    final clampedMs = rawInterval.inMilliseconds.clamp(
      _busAnimationMinDuration.inMilliseconds,
      _busAnimationMaxDuration.inMilliseconds,
    );
    return Duration(milliseconds: clampedMs);
  }

  LatLng? _estimateExtrapolatedPoint(String busMac, DateTime now) {
    final previousPoint = _previousRawBusPositions[busMac];
    final currentPoint = _lastRawBusPositions[busMac];
    final previousUpdatedAt = _previousRawBusUpdatedAt[busMac];
    final currentUpdatedAt = _lastRawBusUpdatedAt[busMac];

    if (previousPoint == null ||
        currentPoint == null ||
        previousUpdatedAt == null ||
        currentUpdatedAt == null) {
      return null;
    }

    final rawIntervalMs =
        currentUpdatedAt.difference(previousUpdatedAt).inMilliseconds;
    if (rawIntervalMs <= 0) {
      return null;
    }

    final extrapolationAge = now.difference(currentUpdatedAt);
    if (extrapolationAge <= Duration.zero ||
        extrapolationAge > _busMaxExtrapolationDuration) {
      return null;
    }

    final rawDistance = getDistanceFromLatLonInM(
      previousPoint.latitude,
      previousPoint.longitude,
      currentPoint.latitude,
      currentPoint.longitude,
    );
    if (rawDistance <= 0) {
      return null;
    }

    final maxExtrapolationRatio = _busMaxExtrapolationDistanceM / rawDistance;
    final extrapolationRatio = math.min(
      extrapolationAge.inMilliseconds / rawIntervalMs,
      maxExtrapolationRatio,
    );
    if (extrapolationRatio <= 0) {
      return null;
    }

    final bus = _latestBusesByMac[busMac];
    final route =
        bus != null ? _resolveRouteForBus(bus, ref.read(routesProvider)) : null;
    final extrapolationDistanceM = math.min(
        rawDistance * extrapolationRatio, _busMaxExtrapolationDistanceM);

    if (route != null && route.waypoints.length >= 2) {
      return _advanceAlongRoute(route, currentPoint, extrapolationDistanceM);
    }

    return LatLng(
      currentPoint.latitude +
          ((currentPoint.latitude - previousPoint.latitude) *
              extrapolationRatio),
      currentPoint.longitude +
          ((currentPoint.longitude - previousPoint.longitude) *
              extrapolationRatio),
    );
  }

  LatLng _advanceAlongRoute(
    BusRoute route,
    LatLng currentPoint,
    double distanceMeters,
  ) {
    if (distanceMeters <= 0 || route.waypoints.length < 2) {
      return currentPoint;
    }

    final segmentIndex = calculateClosestSegmentIndex(route, currentPoint);
    final waypoints = route.waypoints;
    final currentSegmentEndIndex =
        math.min(segmentIndex + 1, waypoints.length - 1);
    final segmentProjection = _projectPointOntoSegment(
      currentPoint,
      waypoints[segmentIndex],
      waypoints[currentSegmentEndIndex],
    );

    var remainingMeters = distanceMeters;
    var startPoint = segmentProjection;

    for (int i = currentSegmentEndIndex; i < waypoints.length; i++) {
      final endPoint = LatLng(waypoints[i].latitude, waypoints[i].longitude);
      final segmentDistance = getDistanceFromLatLonInM(
        startPoint.latitude,
        startPoint.longitude,
        endPoint.latitude,
        endPoint.longitude,
      );

      if (segmentDistance <= 0) {
        startPoint = endPoint;
        continue;
      }

      if (remainingMeters <= segmentDistance) {
        final t = remainingMeters / segmentDistance;
        return LatLng(
          _lerpDouble(startPoint.latitude, endPoint.latitude, t),
          _lerpDouble(startPoint.longitude, endPoint.longitude, t),
        );
      }

      remainingMeters -= segmentDistance;
      startPoint = endPoint;
    }

    return LatLng(
      waypoints.last.latitude,
      waypoints.last.longitude,
    );
  }

  LatLng _projectPointOntoSegment(
    LatLng point,
    Waypoint segmentStart,
    Waypoint segmentEnd,
  ) {
    final dx = segmentEnd.latitude - segmentStart.latitude;
    final dy = segmentEnd.longitude - segmentStart.longitude;
    final lenSq = (dx * dx) + (dy * dy);
    if (lenSq == 0) {
      return LatLng(segmentStart.latitude, segmentStart.longitude);
    }

    final t = (((point.latitude - segmentStart.latitude) * dx) +
            ((point.longitude - segmentStart.longitude) * dy)) /
        lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    return LatLng(
      segmentStart.latitude + (clampedT * dx),
      segmentStart.longitude + (clampedT * dy),
    );
  }

  LatLng? _snappedPointForBus(Bus bus, List<BusRoute> routes) {
    final lat = bus.currentLat;
    final lon = bus.currentLon;
    if (lat == null || lon == null) {
      return null;
    }

    final route = _resolveRouteForBus(bus, routes);
    if (route == null || route.waypoints.length < 2) {
      return LatLng(lat, lon);
    }

    return _projectPointOntoRoute(route, LatLng(lat, lon));
  }

  LatLng? _smoothedPointForBus(Bus bus, List<BusRoute> routes) {
    final snappedPoint = _snappedPointForBus(bus, routes);
    if (snappedPoint == null) {
      return null;
    }

    final previousPoint = _lastRawBusPositions[bus.busMac] ??
        _busAnimationTarget[bus.busMac] ??
        _renderedBusPositions[bus.busMac];
    if (previousPoint == null) {
      return snappedPoint;
    }

    final distanceFromPrevious = getDistanceFromLatLonInM(
      previousPoint.latitude,
      previousPoint.longitude,
      snappedPoint.latitude,
      snappedPoint.longitude,
    );

    if (distanceFromPrevious <= _busSnapJitterHoldDistanceM) {
      return previousPoint;
    }

    if (distanceFromPrevious <= _busSnapBlendDistanceM) {
      return LatLng(
        _lerpDouble(
          previousPoint.latitude,
          snappedPoint.latitude,
          _busSnapBlendFactor,
        ),
        _lerpDouble(
          previousPoint.longitude,
          snappedPoint.longitude,
          _busSnapBlendFactor,
        ),
      );
    }

    return snappedPoint;
  }

  LatLng _projectPointOntoRoute(BusRoute route, LatLng point) {
    final waypoints = route.waypoints;
    if (waypoints.isEmpty) {
      return point;
    }
    if (waypoints.length == 1) {
      return LatLng(waypoints.first.latitude, waypoints.first.longitude);
    }

    var bestPoint = point;
    var bestDistance = double.infinity;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final projected = _projectPointOntoSegment(
        point,
        waypoints[i],
        waypoints[i + 1],
      );
      final distance = getDistanceFromLatLonInM(
        point.latitude,
        point.longitude,
        projected.latitude,
        projected.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = projected;
      }
    }

    return bestPoint;
  }

  Bus _renderedBus(Bus bus) {
    final rendered = _renderedBusPositions[bus.busMac];
    if (rendered == null) {
      return bus;
    }

    return bus.copyWith(
      currentLat: rendered.latitude,
      currentLon: rendered.longitude,
    );
  }

  void _startRideReadyCountdown(IncomingBus candidate) {
    _rideReadyTimer?.cancel();
    final startedAt = DateTime.now();

    setState(() {
      _rideReadyBusMac = candidate.bus.busMac;
      _rideReadySince = startedAt;
    });

    _rideReadyTimer = Timer(_rideDetectionDuration, () {
      if (!mounted) return;
      if (_rideReadyBusMac != candidate.bus.busMac ||
          _rideReadySince != startedAt ||
          _ridingBusMac != null) {
        return;
      }
      setState(() {});
    });
  }

  void _clearRideReadyState() {
    _rideReadyTimer?.cancel();
    _rideReadyTimer = null;

    if (_rideReadyBusMac == null && _rideReadySince == null) {
      return;
    }

    setState(() {
      _rideReadyBusMac = null;
      _rideReadySince = null;
    });
  }

  void _syncRideReadyCandidate(IncomingBus? candidate) {
    if (_ridingBusMac != null || _userLocation == null || candidate == null) {
      if (_rideReadyBusMac != null || _rideReadySince != null) {
        _clearRideReadyState();
      }
      return;
    }

    final effectiveDistance =
        _effectiveRideDistanceM(candidate.distanceM.toDouble());

    if (effectiveDistance > _rideDetectionGraceDistanceM) {
      if (_rideReadyBusMac != null || _rideReadySince != null) {
        _clearRideReadyState();
      }
      return;
    }

    if (effectiveDistance > _rideDetectionDistanceM) {
      if (_rideReadyBusMac != candidate.bus.busMac &&
          (_rideReadyBusMac != null || _rideReadySince != null)) {
        _clearRideReadyState();
      }
      return;
    }

    if (_rideReadyBusMac != candidate.bus.busMac) {
      _startRideReadyCountdown(candidate);
    }
  }

  bool _isRideReadyFor(String busMac) {
    if (_rideReadyBusMac != busMac || _rideReadySince == null) {
      return false;
    }

    return DateTime.now().difference(_rideReadySince!) >=
        _rideDetectionDuration;
  }

  double _effectiveRideDistanceM(double measuredDistanceM) {
    final accuracy = _userLocation?.accuracy;
    if (accuracy == null || accuracy.isNaN) {
      return measuredDistanceM;
    }

    final compensation =
        accuracy.clamp(0, _rideGpsAccuracyCompensationCapM).toDouble();
    return math.max(0, measuredDistanceM - compensation);
  }

  void _startRideSessionMonitor() {
    _rideSessionMonitorTimer?.cancel();
    _refreshRideSessionStatus();
    _rideSessionMonitorTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshRideSessionStatus(),
    );
  }

  Future<void> _refreshRideSessionStatus() async {
    final sessionId = _activeRideSessionId;
    if (!mounted || _ridingBusMac == null || sessionId == null) {
      return;
    }

    try {
      final status = await _busService.getRideStatus(sessionId);
      if (!mounted) return;

      if (!status.active || status.session == null) {
        _rideSessionMonitorTimer?.cancel();
        setState(() {
          _isRingBellAvailable = false;
          _activeRideSessionId = null;
        });
        return;
      }

      setState(() {
        _isRingBellAvailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRingBellAvailable = false;
      });
    }
  }

  Future<void> _startRide(IncomingBus busInfo) async {
    final passengerCount = busInfo.bus.personCount;
    if (passengerCount == null || passengerCount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            passengerCount == null
                ? 'Passenger count is not available yet.'
                : 'Cannot start ride while the bus is empty.',
          ),
        ),
      );
      return;
    }

    final userLocation = _userLocation;
    if (userLocation == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is required before starting a ride.'),
        ),
      );
      return;
    }

    setState(() {
      _isStartingRide = true;
    });

    try {
      final rideSession = await _busService.startRideSession(
        busMac: busInfo.bus.busMac,
        userLat: userLocation.latitude,
        userLon: userLocation.longitude,
        userAccuracyM: userLocation.accuracy,
      );
      final route = _resolveRouteForBus(busInfo.bus, ref.read(routesProvider));

      if (!mounted) return;

      setState(() {
        _ridingBusMac = busInfo.bus.busMac;
        _activeBusMac = busInfo.bus.busMac;
        _activeRoute = route;
        _rideReadyBusMac = null;
        _rideReadySince = null;
        _activeRideSessionId = rideSession.sessionId;
        _isRingBellAvailable = true;
        _isStartingRide = false;

        if (route != null &&
            busInfo.bus.currentLat != null &&
            busInfo.bus.currentLon != null) {
          _currentStopIndex = calculateNextStopIndex(
            route,
            LatLng(busInfo.bus.currentLat!, busInfo.bus.currentLon!),
            bus: busInfo.bus,
          );
        }
      });

      _rideReadyTimer?.cancel();
      _rideReadyTimer = null;
      _startRideSessionMonitor();

      if (busInfo.bus.currentLat != null && busInfo.bus.currentLon != null) {
        _mapController.move(
          LatLng(busInfo.bus.currentLat!, busInfo.bus.currentLon!),
          17.0,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStartingRide = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start ride: $e')),
      );
    }
  }

  Future<void> _cancelRide() async {
    final sessionId = _activeRideSessionId;
    _rideSessionMonitorTimer?.cancel();
    if (sessionId != null) {
      await _busService.endRideSession(sessionId);
    }

    if (!mounted) return;
    setState(() {
      _ridingBusMac = null;
      _activeBusMac = null;
      _activeRoute = null;
      _rideReadyBusMac = null;
      _rideReadySince = null;
      _activeRideSessionId = null;
      _isRingBellAvailable = false;
      _isStartingRide = false;
      _isRingingBell = false;
    });

    _rideReadyTimer?.cancel();
    _rideReadyTimer = null;
  }

  Future<void> _ringBus(Bus bus) async {
    final messenger = ScaffoldMessenger.of(context);
    final sessionId = _activeRideSessionId;
    final userLocation = _userLocation;

    if (sessionId == null || userLocation == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('You must be actively riding this bus to ring.'),
        ),
      );
      return;
    }

    setState(() {
      _isRingingBell = true;
    });

    try {
      await _busService.ringBell(
        busMac: bus.busMac,
        sessionId: sessionId,
        userLat: userLocation.latitude,
        userLon: userLocation.longitude,
        userAccuracyM: userLocation.accuracy,
      );
      if (!mounted) return;

      setState(() {
        _isRingingBell = false;
        _isRingBellAvailable = true;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Drop-off bell sent!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRingingBell = false;
        _isRingBellAvailable = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to send ring: ${e.toString()}')),
      );
    }
  }

  Position _spoofedPositionFromLatLng(LatLng point) {
    return Position(
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
  }

  void _updateSpoofedUserLocation(LatLng point, {bool showFeedback = true}) {
    setState(() {
      _userLocation = _spoofedPositionFromLatLng(point);
    });

    if (!showFeedback) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Spoofed user location updated.'),
        duration: Duration(milliseconds: 700),
      ),
    );
  }

  void _handleTestMarkerDragEnd(DraggableDetails details) {
    final renderObject =
        _mapViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null) {
      return;
    }

    final localOffset = renderObject.globalToLocal(details.offset);
    final clampedOffset = Offset(
      localOffset.dx.clamp(0.0, math.max(renderObject.size.width - 1, 0)),
      localOffset.dy.clamp(0.0, math.max(renderObject.size.height - 1, 0)),
    );

    final target = _mapController.camera.offsetToCrs(clampedOffset);
    _updateSpoofedUserLocation(target);
  }

  Widget _buildUserMarker(bool testModeEnabled) {
    final markerCore = Container(
      decoration: BoxDecoration(
        color: testModeEnabled
            ? Colors.deepPurple.withValues(alpha: 0.2)
            : Colors.blue.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: testModeEnabled ? Colors.deepPurple : Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );

    if (!testModeEnabled) {
      return markerCore;
    }

    return LongPressDraggable<Object>(
      data: const Object(),
      onDragEnd: _handleTestMarkerDragEnd,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 40,
          height: 40,
          child: markerCore,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: markerCore,
      ),
      child: Tooltip(
        message: 'Long press and drag to spoof your location',
        child: markerCore,
      ),
    );
  }

  List<Marker> _buildStopMarkers(
    List<BusRoute> allRoutes, {
    BusRoute? focusedRoute,
    int? nextStopIndex,
  }) {
    return allRoutes.expand((route) {
      return route.stops.asMap().entries.map((entry) {
        final i = entry.key;
        final stop = entry.value;
        final stopKey = _stopMarkerKey(route, stop, i);
        final isSelectedStop = _selectedStopKey == stopKey;
        final isFocusedStopSet =
            focusedRoute != null && route.routeId == focusedRoute.routeId;
        final isNext = isFocusedStopSet && i == nextStopIndex;
        final selectedFocusStopIndex = isFocusedStopSet &&
                _selectedStopRouteId == route.routeId &&
                _selectedStopRouteIndex != null &&
                nextStopIndex != null &&
                _selectedStopRouteIndex! >= nextStopIndex
            ? _selectedStopRouteIndex
            : null;
        final focusedWindowEndExclusive = selectedFocusStopIndex != null
            ? selectedFocusStopIndex + 1
            : (nextStopIndex != null ? nextStopIndex + 5 : null);
        final focusedOffsetIndex =
            nextStopIndex != null ? i - nextStopIndex : -1;
        final isPassed =
            isFocusedStopSet && nextStopIndex != null && i < nextStopIndex;
        final isUpcomingWithinFocusWindow = isFocusedStopSet &&
            nextStopIndex != null &&
            focusedWindowEndExclusive != null &&
            i >= nextStopIndex &&
            i < focusedWindowEndExclusive;
        final shouldShowLabel = isUpcomingWithinFocusWindow || isSelectedStop;
        final markerFillColor = isPassed ? _mapAccent : Colors.white;
        final markerBorderColor =
            isFocusedStopSet ? _mapAccent : const Color(0xFFD1D5DB);

        return Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: shouldShowLabel ? 104 : 34,
          height: shouldShowLabel ? 44 : 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _selectedStopKey = stopKey;
                _selectedStopRouteId = route.routeId;
                _selectedStopRouteIndex = isFocusedStopSet &&
                        nextStopIndex != null &&
                        i >= nextStopIndex
                    ? i
                    : null;
              });
            },
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: markerFillColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: markerBorderColor,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          spreadRadius: 1),
                    ],
                  ),
                ),
                if (shouldShowLabel)
                  Positioned(
                    top: isSelectedStop
                        ? -8
                        : focusedOffsetIndex.isEven
                            ? -6
                            : 20,
                    left: isSelectedStop
                        ? 17
                        : focusedOffsetIndex.isEven
                            ? 22
                            : null,
                    right: isSelectedStop
                        ? null
                        : focusedOffsetIndex.isEven
                            ? null
                            : 22,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 88),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isNext
                              ? _mapAccent.withValues(alpha: 0.28)
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        stop.stopName ?? 'Stop',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.1,
                          fontWeight:
                              isNext ? FontWeight.w800 : FontWeight.w600,
                          color: isNext ? _mapAccent : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      });
    }).toList();
  }

  String _stopMarkerKey(BusRoute route, Waypoint stop, int stopIndex) {
    return '${route.routeId}:$stopIndex:${stop.stopName}:${stop.latitude}:${stop.longitude}';
  }

  List<Polyline> _buildRoutePolylines(
    List<BusRoute> allRoutes, {
    BusRoute? focusedRoute,
    Bus? focusedBus,
  }) {
    final backgroundRoutes = allRoutes.map((route) {
      final isFocused =
          focusedRoute != null && route.routeId == focusedRoute.routeId;
      return Polyline(
        points: route.waypoints
            .map((w) => LatLng(w.latitude, w.longitude))
            .toList(),
        color: isFocused
            ? const Color(0xFFCBD5E1).withValues(alpha: 0.55)
            : const Color(0xFFE5E7EB).withValues(alpha: 0.35),
        strokeWidth: isFocused ? 3.5 : 3,
        borderStrokeWidth: 0,
      );
    }).toList();

    if (focusedRoute == null ||
        focusedBus?.currentLat == null ||
        focusedBus?.currentLon == null) {
      return backgroundRoutes;
    }

    final activeBus = focusedBus;
    final busPoint = LatLng(activeBus!.currentLat!, activeBus.currentLon!);
    final nextStop = _resolveStableNextStopForBus(
      focusedRoute,
      activeBus,
      busPoint,
    );
    final currentSegmentIndex = nextStop?.stopIndex != null
        ? _findCurrentLegSegmentIndex(
            focusedRoute, busPoint, nextStop!.stopIndex)
        : calculateClosestSegmentIndex(focusedRoute, busPoint);
    final nextStopRouteIndex = nextStop != null
        ? _stopRouteIndexForWaypointIndex(focusedRoute, nextStop.stopIndex)
        : null;
    final selectedFocusStopIndex =
        _selectedStopRouteId == focusedRoute.routeId &&
                _selectedStopRouteIndex != null &&
                nextStopRouteIndex != null &&
                _selectedStopRouteIndex! >= nextStopRouteIndex
            ? _selectedStopRouteIndex
            : null;
    final selectedFocusWaypointIndex = selectedFocusStopIndex != null
        ? _waypointIndexForStopRouteIndex(focusedRoute, selectedFocusStopIndex)
        : null;
    final upcomingPoints = _buildUpcomingPathPoints(
      focusedRoute,
      busPoint,
      stopCount: 5,
      nextStopWaypointIndex: nextStop?.stopIndex,
      targetWaypointIndex: selectedFocusWaypointIndex,
    );
    final passedPoints = nextStopRouteIndex != null && nextStopRouteIndex > 0
        ? _buildPassedPathPoints(
            focusedRoute,
            busPoint,
            currentSegmentIndex: currentSegmentIndex,
          )
        : const <LatLng>[];

    return [
      ...backgroundRoutes,
      if (passedPoints.length >= 2)
        Polyline(
          points: passedPoints,
          color: const Color(0xFF94A3B8),
          strokeWidth: 5,
          borderStrokeWidth: 1.5,
          borderColor: Colors.white.withValues(alpha: 0.8),
        ),
      if (upcomingPoints.length >= 2)
        Polyline(
          points: upcomingPoints,
          color: _mapAccent,
          strokeWidth: 5,
          borderStrokeWidth: 2,
          borderColor: Colors.white.withValues(alpha: 0.88),
        ),
    ];
  }

  List<LatLng> _buildPassedPathPoints(
    BusRoute route,
    LatLng busPoint, {
    required int currentSegmentIndex,
  }) {
    final waypoints = route.waypoints;
    if (waypoints.isEmpty) {
      return const [];
    }

    final points = <LatLng>[
      LatLng(waypoints.first.latitude, waypoints.first.longitude),
    ];

    for (int i = 1; i <= currentSegmentIndex && i < waypoints.length; i++) {
      points.add(LatLng(waypoints[i].latitude, waypoints[i].longitude));
    }

    points.add(busPoint);
    return points;
  }

  int? _stopRouteIndexForWaypointIndex(BusRoute route, int waypointIndex) {
    var stopRouteIndex = 0;
    for (int i = 0; i < route.waypoints.length; i++) {
      final waypoint = route.waypoints[i];
      if (waypoint.isStop && (waypoint.stopName?.trim().isNotEmpty ?? false)) {
        if (i == waypointIndex) {
          return stopRouteIndex;
        }
        stopRouteIndex++;
      }
    }
    return null;
  }

  int? _waypointIndexForStopRouteIndex(BusRoute route, int stopRouteIndex) {
    var currentStopRouteIndex = 0;
    for (int i = 0; i < route.waypoints.length; i++) {
      final waypoint = route.waypoints[i];
      if (waypoint.isStop && (waypoint.stopName?.trim().isNotEmpty ?? false)) {
        if (currentStopRouteIndex == stopRouteIndex) {
          return i;
        }
        currentStopRouteIndex++;
      }
    }
    return null;
  }

  List<LatLng> _buildUpcomingPathPoints(
    BusRoute route,
    LatLng busPoint, {
    int stopCount = 5,
    int? nextStopWaypointIndex,
    int? targetWaypointIndex,
    LatLng? userPoint,
  }) {
    final waypoints = route.waypoints;
    if (waypoints.isEmpty) {
      return [busPoint];
    }

    final segmentIndex = nextStopWaypointIndex != null
        ? _findCurrentLegSegmentIndex(route, busPoint, nextStopWaypointIndex)
        : calculateClosestSegmentIndex(route, busPoint);
    final points = <LatLng>[busPoint];
    var seenStops = 0;

    for (int step = 1; step <= waypoints.length; step++) {
      final waypointIndex = (segmentIndex + step) % waypoints.length;
      final waypoint = waypoints[waypointIndex];
      points.add(LatLng(waypoint.latitude, waypoint.longitude));

      if (targetWaypointIndex != null) {
        if (waypointIndex == targetWaypointIndex) {
          break;
        }
        continue;
      }

      if (waypoint.isStop && (waypoint.stopName?.trim().isNotEmpty ?? false)) {
        seenStops++;
        if (seenStops >= stopCount) {
          break;
        }
      }
    }

    if (targetWaypointIndex != null && userPoint != null) {
      points.add(userPoint);
    }

    return points;
  }

  int _findCurrentLegSegmentIndex(
    BusRoute route,
    LatLng busPoint,
    int nextStopWaypointIndex,
  ) {
    final waypoints = route.waypoints;
    if (waypoints.length < 2) {
      return 0;
    }

    final normalizedNextStopIndex =
        nextStopWaypointIndex.clamp(0, waypoints.length - 1);
    var previousStopIndex = normalizedNextStopIndex;

    for (int step = 1; step <= waypoints.length; step++) {
      final candidateIndex =
          (normalizedNextStopIndex - step + waypoints.length) %
              waypoints.length;
      final candidate = waypoints[candidateIndex];
      if (candidate.isStop &&
          (candidate.stopName?.trim().isNotEmpty ?? false)) {
        previousStopIndex = candidateIndex;
        break;
      }
    }

    double minDistance = double.infinity;
    var bestSegmentIndex = previousStopIndex;
    var cursor = previousStopIndex;

    while (cursor != normalizedNextStopIndex) {
      final nextIndex = (cursor + 1) % waypoints.length;
      final segStart = waypoints[cursor];
      final segEnd = waypoints[nextIndex];
      final distance = _distanceToSegmentSquared(
        busPoint,
        LatLng(segStart.latitude, segStart.longitude),
        LatLng(segEnd.latitude, segEnd.longitude),
      );
      if (distance < minDistance) {
        minDistance = distance;
        bestSegmentIndex = cursor;
      }
      cursor = nextIndex;
    }

    return bestSegmentIndex;
  }

  double _distanceToSegmentSquared(
    LatLng point,
    LatLng segStart,
    LatLng segEnd,
  ) {
    final dx = segEnd.latitude - segStart.latitude;
    final dy = segEnd.longitude - segStart.longitude;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      final dLat = point.latitude - segStart.latitude;
      final dLon = point.longitude - segStart.longitude;
      return dLat * dLat + dLon * dLon;
    }

    final t = ((point.latitude - segStart.latitude) * dx +
            (point.longitude - segStart.longitude) * dy) /
        lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    final projLat = segStart.latitude + clampedT * dx;
    final projLon = segStart.longitude + clampedT * dy;
    final dLat = point.latitude - projLat;
    final dLon = point.longitude - projLon;
    return dLat * dLat + dLon * dLon;
  }

  void _onBusTap(Bus bus) {
    final routes = ref.read(routesProvider);
    final route = _resolveRouteForBus(bus, routes);

    setState(() {
      _activeRoute = route;
      _activeBusMac = bus.busMac;
      _selectedInfoBusMac = bus.busMac;
      _selectedStopKey = null;
      _selectedStopRouteId = null;
      _selectedStopRouteIndex = null;
      if (bus.currentLat != null && bus.currentLon != null && route != null) {
        _currentStopIndex = calculateNextStopIndex(
          route,
          LatLng(bus.currentLat!, bus.currentLon!),
          bus: bus,
        );
      }
    });
    _moveCameraToFollowBus(
      LatLng(bus.currentLat!, bus.currentLon!),
      zoom: 16.5,
    );
  }

  int calculateBusStopIndex(BusRoute route, LatLng busPosition) {
    final closestSegmentIndex =
        calculateClosestSegmentIndex(route, busPosition);
    int passedStops = 0;
    for (int i = 0; i <= closestSegmentIndex; i++) {
      if (route.waypoints[i].isStop && route.waypoints[i].stopName != null) {
        passedStops++;
      }
    }
    return passedStops;
  }

  int calculateNextStopIndex(
    BusRoute route,
    LatLng busPosition, {
    Bus? bus,
  }) {
    final nextStop = bus != null
        ? _resolveStableNextStopForBus(route, bus, busPosition)
        : _findNextStopAlongRoute(route, busPosition);
    if (nextStop == null) {
      return calculateBusStopIndex(route, busPosition);
    }

    final stopIndex = route.stops.indexWhere(
      (stop) => stop.stopName == nextStop.stopName,
    );
    return stopIndex >= 0
        ? stopIndex
        : calculateBusStopIndex(route, busPosition);
  }

  int calculateClosestSegmentIndex(BusRoute route, LatLng busPosition) {
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
    return closestSegmentIndex;
  }

  int _estimateEtaMinutes(double distanceM) {
    const avgBusSpeedMs = 25 * 1000 / 3600;
    return (distanceM / avgBusSpeedMs / 60).round().clamp(1, 999);
  }

  NextStopResult _buildNextStopResultFromWaypoint(
    Waypoint waypoint,
    int waypointIndex,
    LatLng busPosition,
  ) {
    final distance = getDistanceFromLatLonInM(
      busPosition.latitude,
      busPosition.longitude,
      waypoint.latitude,
      waypoint.longitude,
    );
    return NextStopResult(
      stopName: waypoint.stopName ?? '-',
      stopIndex: waypointIndex,
      distanceM: distance.round(),
      etaMinutes: _estimateEtaMinutes(distance),
    );
  }

  NextStopResult? _findSubsequentStopFromWaypointIndex(
    BusRoute route,
    int waypointIndex,
    LatLng busPosition, {
    bool forward = true,
  }) {
    final waypoints = route.waypoints;
    if (forward) {
      for (int i = waypointIndex + 1; i < waypoints.length; i++) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }

      for (int i = 0; i <= waypointIndex && i < waypoints.length; i++) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }
    } else {
      for (int i = waypointIndex; i >= 0; i--) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }

      for (int i = waypoints.length - 1; i > waypointIndex; i--) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }
    }

    return null;
  }

  NextStopResult? _findNextStopAlongRoute(
    BusRoute route,
    LatLng busPosition, {
    bool forward = true,
  }) {
    if (route.waypoints.isEmpty) {
      return null;
    }

    final segmentIndex = calculateClosestSegmentIndex(route, busPosition);
    final waypoints = route.waypoints;

    if (forward) {
      for (int i = segmentIndex + 1; i < waypoints.length; i++) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }

      for (int i = 0; i <= segmentIndex && i < waypoints.length; i++) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }
    } else {
      for (int i = segmentIndex; i >= 0; i--) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }

      for (int i = waypoints.length - 1; i > segmentIndex; i--) {
        final wp = waypoints[i];
        if (wp.isStop &&
            wp.stopName != null &&
            wp.stopName!.trim().isNotEmpty) {
          return _buildNextStopResultFromWaypoint(wp, i, busPosition);
        }
      }
    }

    return null;
  }

  NextStopResult? _resolveStableNextStopForBus(
    BusRoute route,
    Bus bus,
    LatLng busPosition,
  ) {
    final isMovingForward = _isBusMovingForwardOnRoute(route, bus, busPosition);
    final candidate = _findNextStopAlongRoute(
      route,
      busPosition,
      forward: isMovingForward,
    );
    final lockedIndex = _lockedNextStopWaypointIndexByBus[bus.busMac];
    final previousRawPoint = _previousRawBusPositions[bus.busMac];

    if (lockedIndex != null &&
        lockedIndex >= 0 &&
        lockedIndex < route.waypoints.length) {
      final lockedWaypoint = route.waypoints[lockedIndex];
      if (lockedWaypoint.isStop &&
          lockedWaypoint.stopName != null &&
          lockedWaypoint.stopName!.trim().isNotEmpty) {
        final lockedStop = _buildNextStopResultFromWaypoint(
            lockedWaypoint, lockedIndex, busPosition);
        final lockedDistance = lockedStop.distanceM ?? 0;
        final candidateDistance = candidate?.distanceM ?? 1 << 30;

        if (lockedDistance <= _stopArrivalDistanceM) {
          final advanced = _findSubsequentStopFromWaypointIndex(
            route,
            lockedIndex,
            busPosition,
            forward: isMovingForward,
          );
          if (advanced != null) {
            _lockedNextStopWaypointIndexByBus[bus.busMac] = advanced.stopIndex;
            return advanced;
          }
        }

        final previousLockedDistance = previousRawPoint == null
            ? null
            : getDistanceFromLatLonInM(
                previousRawPoint.latitude,
                previousRawPoint.longitude,
                lockedWaypoint.latitude,
                lockedWaypoint.longitude,
              );
        final isMovingAwayFromLockedStop = previousLockedDistance != null &&
            lockedDistance > previousLockedDistance + 5;
        final shouldHoldLockedStop = !isMovingAwayFromLockedStop &&
            (isMovingForward
                ? lockedIndex <= (candidate?.stopIndex ?? lockedIndex)
                : lockedIndex >= (candidate?.stopIndex ?? lockedIndex)) &&
            lockedDistance <= _nextStopHoldDistanceM &&
            lockedDistance <= candidateDistance + _nextStopReleaseDistanceM;

        if (shouldHoldLockedStop) {
          return lockedStop;
        }
      }
    }

    if (candidate != null) {
      if ((candidate.distanceM ?? 1 << 30) <= _stopArrivalDistanceM) {
        final advanced = _findSubsequentStopFromWaypointIndex(
          route,
          candidate.stopIndex,
          busPosition,
          forward: isMovingForward,
        );
        if (advanced != null) {
          _lockedNextStopWaypointIndexByBus[bus.busMac] = advanced.stopIndex;
          return advanced;
        }
      }
      _lockedNextStopWaypointIndexByBus[bus.busMac] = candidate.stopIndex;
    }
    return candidate;
  }

  bool _isBusMovingForwardOnRoute(BusRoute route, Bus bus, LatLng busPosition) {
    final previousRawPoint = _previousRawBusPositions[bus.busMac];
    final currentRawPoint = _lastRawBusPositions[bus.busMac] ?? busPosition;

    if (previousRawPoint == null ||
        _pointDistanceSquared(previousRawPoint, currentRawPoint) == 0) {
      return true;
    }

    final segmentIndex = calculateClosestSegmentIndex(route, currentRawPoint);
    final waypoints = route.waypoints;
    if (segmentIndex < 0 || segmentIndex >= waypoints.length - 1) {
      return true;
    }

    final segStart = LatLng(
      waypoints[segmentIndex].latitude,
      waypoints[segmentIndex].longitude,
    );
    final segEnd = LatLng(
      waypoints[segmentIndex + 1].latitude,
      waypoints[segmentIndex + 1].longitude,
    );
    final routeDx = segEnd.longitude - segStart.longitude;
    final routeDy = segEnd.latitude - segStart.latitude;
    final motionDx = currentRawPoint.longitude - previousRawPoint.longitude;
    final motionDy = currentRawPoint.latitude - previousRawPoint.latitude;
    final dot = (routeDx * motionDx) + (routeDy * motionDy);

    return dot >= 0;
  }

  ({Waypoint stop, int waypointIndex, double walkingDistanceM})?
      _findNearestStopOnRoute(
    BusRoute route,
    LatLng userLocation,
  ) {
    Waypoint? closest;
    int closestWaypointIndex = -1;
    double closestDistance = double.infinity;

    for (int i = 0; i < route.waypoints.length; i++) {
      final waypoint = route.waypoints[i];
      if (!waypoint.isStop ||
          !(waypoint.stopName?.trim().isNotEmpty ?? false)) {
        continue;
      }

      final distance = getDistanceFromLatLonInM(
        userLocation.latitude,
        userLocation.longitude,
        waypoint.latitude,
        waypoint.longitude,
      );
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = waypoint;
        closestWaypointIndex = i;
      }
    }

    if (closest == null || closestWaypointIndex == -1) {
      return null;
    }

    return (
      stop: closest,
      waypointIndex: closestWaypointIndex,
      walkingDistanceM: closestDistance,
    );
  }

  ({double distanceM, int stopsAway}) _measureRouteToWaypoint(
    BusRoute route,
    LatLng busPoint,
    int targetWaypointIndex,
  ) {
    final waypoints = route.waypoints;
    if (waypoints.isEmpty) {
      return (distanceM: 0, stopsAway: 0);
    }

    final segmentIndex = calculateClosestSegmentIndex(route, busPoint);
    var totalDistance = 0.0;
    var stopsAway = 0;
    var previousPoint = busPoint;

    for (int step = 1; step <= waypoints.length; step++) {
      final waypointIndex = (segmentIndex + step) % waypoints.length;
      final waypoint = waypoints[waypointIndex];
      final currentPoint = LatLng(waypoint.latitude, waypoint.longitude);

      totalDistance += getDistanceFromLatLonInM(
        previousPoint.latitude,
        previousPoint.longitude,
        currentPoint.latitude,
        currentPoint.longitude,
      );

      if (waypoint.isStop && (waypoint.stopName?.trim().isNotEmpty ?? false)) {
        stopsAway++;
      }

      if (waypointIndex == targetWaypointIndex) {
        break;
      }

      previousPoint = currentPoint;
    }

    return (
      distanceM: totalDistance,
      stopsAway: stopsAway,
    );
  }

  BusArrivalDetails? _buildArrivalDetailsForBus(
    Bus bus,
    BusRoute route,
    LatLng userLocation,
  ) {
    if (bus.currentLat == null || bus.currentLon == null) {
      return null;
    }

    final busPoint = LatLng(bus.currentLat!, bus.currentLon!);
    final nextStop = _resolveStableNextStopForBus(route, bus, busPoint);
    final target = _findNearestStopOnRoute(route, userLocation);
    if (target == null) {
      return null;
    }

    final routeMeasure =
        _measureRouteToWaypoint(route, busPoint, target.waypointIndex);

    return BusArrivalDetails(
      nextStop: nextStop,
      targetStop: target.stop,
      targetWaypointIndex: target.waypointIndex,
      etaMinutes: _estimateEtaMinutes(routeMeasure.distanceM),
      distanceM: routeMeasure.distanceM.round(),
      stopsAway: routeMeasure.stopsAway,
      walkingDistanceM: target.walkingDistanceM,
    );
  }

  List<Waypoint> _nextStopsForBus(
    BusRoute route,
    Bus bus, {
    int count = 5,
  }) {
    if (bus.currentLat == null ||
        bus.currentLon == null ||
        route.waypoints.isEmpty) {
      return const [];
    }

    final nextStop = _resolveStableNextStopForBus(
      route,
      bus,
      LatLng(bus.currentLat!, bus.currentLon!),
    );
    final stops = route.stops;
    if (stops.isEmpty) {
      return const [];
    }

    var startIndex = 0;
    if (nextStop != null) {
      final idx =
          stops.indexWhere((stop) => stop.stopName == nextStop.stopName);
      if (idx >= 0) {
        startIndex = idx;
      }
    }

    final result = <Waypoint>[];
    for (int i = 0; i < count && i < stops.length; i++) {
      result.add(stops[(startIndex + i) % stops.length]);
    }
    return result;
  }

  BusRoute? _resolveRouteForBus(Bus bus, List<BusRoute> routes) {
    if (bus.routeId != null && bus.routeId!.isNotEmpty) {
      final matched =
          routes.where((route) => route.routeId == bus.routeId).firstOrNull;
      if (matched != null) {
        return matched;
      }
    }

    if (bus.currentLat == null || bus.currentLon == null || routes.isEmpty) {
      return null;
    }

    final busPosition = LatLng(bus.currentLat!, bus.currentLon!);
    BusRoute? closestRoute;
    double closestDistance = double.infinity;

    for (final route in routes) {
      final distance = _distanceToRoute(route, busPosition);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestRoute = route;
      }
    }

    // Keep the fallback conservative so we don't snap a bus to a random route.
    return closestDistance <= 120 ? closestRoute : null;
  }

  double _distanceToRoute(BusRoute route, LatLng point) {
    if (route.waypoints.isEmpty) return double.infinity;
    if (route.waypoints.length == 1) {
      final wp = route.waypoints.first;
      return getDistanceFromLatLonInM(
        point.latitude,
        point.longitude,
        wp.latitude,
        wp.longitude,
      );
    }

    double minDistance = double.infinity;
    for (int i = 0; i < route.waypoints.length - 1; i++) {
      final start = route.waypoints[i];
      final end = route.waypoints[i + 1];
      final distance = _distanceToSegment(
        point,
        LatLng(start.latitude, start.longitude),
        LatLng(end.latitude, end.longitude),
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  double _distanceToSegment(LatLng point, LatLng start, LatLng end) {
    final dx = end.latitude - start.latitude;
    final dy = end.longitude - start.longitude;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      return getDistanceFromLatLonInM(
        point.latitude,
        point.longitude,
        start.latitude,
        start.longitude,
      );
    }

    final t = (((point.latitude - start.latitude) * dx) +
            ((point.longitude - start.longitude) * dy)) /
        lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    final projectedLat = start.latitude + clampedT * dx;
    final projectedLon = start.longitude + clampedT * dy;

    return getDistanceFromLatLonInM(
      point.latitude,
      point.longitude,
      projectedLat,
      projectedLon,
    );
  }

  Widget _buildBusInfoSheet({
    required Bus bus,
    required BusRoute? route,
    required String nextStopName,
    required int? etaToUser,
    required int? stopsAway,
  }) {
    if (bus.isOffline) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _selectedBusDockMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: Image.asset(
                          'assets/images/bus_icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bus.busName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedInfoBusMac = null;
                          });
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This bus is offline',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: _selectedBusDockMaxWidth,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: Image.asset(
                        'assets/images/bus_icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bus.busName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedInfoBusMac = null;
                        });
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoStat(
                          'NEXT STOP', nextStopName, CrossAxisAlignment.start),
                    ),
                    Expanded(
                      child: _buildInfoStat(
                        'ETA',
                        etaToUser != null ? '$etaToUser min' : '-',
                        CrossAxisAlignment.center,
                      ),
                    ),
                    Expanded(
                      child: _buildInfoStat(
                        'STOPS AWAY',
                        stopsAway != null ? '$stopsAway' : '-',
                        CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStat(
    String label,
    String value,
    CrossAxisAlignment alignment,
  ) {
    final textAlign = alignment == CrossAxisAlignment.start
        ? TextAlign.left
        : alignment == CrossAxisAlignment.end
            ? TextAlign.right
            : TextAlign.center;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
          textAlign: textAlign,
        ),
      ],
    );
  }

  Widget _buildSelectedBusOverlay(List<Bus> buses, List<BusRoute> routes) {
    if (_selectedInfoBusMac == null) {
      return const SizedBox.shrink();
    }

    final bus =
        buses.where((item) => item.busMac == _selectedInfoBusMac).firstOrNull;
    if (bus == null) {
      return const SizedBox.shrink();
    }

    final route = _resolveRouteForBus(bus, routes);
    final arrivalDetails = route != null && _userLocation != null
        ? _buildArrivalDetailsForBus(
            bus,
            route,
            LatLng(_userLocation!.latitude, _userLocation!.longitude),
          )
        : null;
    final nextStopName = arrivalDetails?.nextStop?.stopName ??
        (route != null
            ? _nextStopsForBus(route, bus, count: 1).firstOrNull?.stopName ??
                '-'
            : '-');

    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 16,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Center(
          child: _buildBusInfoSheet(
            bus: bus,
            route: route,
            nextStopName: nextStopName,
            etaToUser: arrivalDetails?.etaMinutes,
            stopsAway: arrivalDetails?.stopsAway,
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyPanel(List<BusRoute> routes, List<Bus> buses) {
    if (_userLocation == null) return const SizedBox.shrink();

    final testModeEnabled = ref.read(testModeProvider).enabled;
    final nearbyCandidateBuses = testModeEnabled
        ? buses
        : buses.where((bus) => !bus.isDebugBus).toList();
    final onlineNearbyCandidateBuses =
        nearbyCandidateBuses.where((bus) => !bus.isOffline).toList();

    final allStops = routes.expand((r) => r.stops).toList();
    final nearest = findNearestStop(
      LatLng(_userLocation!.latitude, _userLocation!.longitude),
      allStops,
    );

    if (nearest == null || nearest.distance > 800) {
      return const SizedBox.shrink();
    }

    final displayBus = findClosestBusToUser(
      LatLng(_userLocation!.latitude, _userLocation!.longitude),
      onlineNearbyCandidateBuses,
      routes,
    );
    final displayBusRoute =
        displayBus != null ? _resolveRouteForBus(displayBus.bus, routes) : null;
    final displayBusArrival = displayBus != null && displayBusRoute != null
        ? _buildArrivalDetailsForBus(
            displayBus.bus,
            displayBusRoute,
            LatLng(_userLocation!.latitude, _userLocation!.longitude),
          )
        : null;
    final incomingBuses = calculateIncomingBuses(
      displayBusArrival?.targetStop ?? nearest.stop,
      onlineNearbyCandidateBuses,
      routes,
    );
    final ridingBus = _ridingBusMac == null
        ? null
        : buses.where((bus) => bus.busMac == _ridingBusMac).firstOrNull;
    final isRidingBusOffline = ridingBus?.isOffline ?? false;
    final ridingRoute =
        ridingBus != null ? _resolveRouteForBus(ridingBus, routes) : null;
    final nextStop = ridingBus != null
        ? findNextStop(
            ridingBus.currentLat,
            ridingBus.currentLon,
            ridingRoute?.waypoints ?? <Waypoint>[],
          )
        : null;
    final actionBus = ridingBus ?? displayBus?.bus;
    final isRideDistanceReady = displayBus != null &&
        _effectiveRideDistanceM(displayBus.distanceM.toDouble()) <=
            _rideDetectionDistanceM &&
        _isRideReadyFor(displayBus.bus.busMac);
    final ridePassengerCount = displayBus?.bus.personCount;
    final hasRidePassengerCount = ridePassengerCount != null;
    final hasRidePassengers = (ridePassengerCount ?? 0) > 0;
    final canRide = isRideDistanceReady && hasRidePassengers;
    final rideButtonLabel = _isStartingRide
        ? 'STARTING...'
        : !isRideDistanceReady
            ? 'GET CLOSER TO RIDE'
            : !hasRidePassengerCount
                ? 'COUNT UNKNOWN'
                : !hasRidePassengers
                    ? 'BUS EMPTY'
                    : 'RIDE';
    final rideButtonIcon = _isStartingRide
        ? Icons.hourglass_top_rounded
        : !isRideDistanceReady
            ? Icons.near_me_rounded
            : !hasRidePassengers
                ? Icons.people_alt_rounded
                : Icons.airport_shuttle_rounded;
    final hasOfflineCandidates =
        nearbyCandidateBuses.any((bus) => bus.isOffline);
    final shouldShowOfflineState = _ridingBusMac != null
        ? isRidingBusOffline
        : displayBus == null &&
            hasOfflineCandidates &&
            onlineNearbyCandidateBuses.isEmpty;
    final offlineBus = _ridingBusMac != null
        ? ridingBus
        : nearbyCandidateBuses.where((bus) => bus.isOffline).firstOrNull;
    final incomingPassengerCount = actionBus?.personCount;
    final incomingPassengerLabel =
        incomingPassengerCount == null ? '--/40' : '$incomingPassengerCount/40';
    final incomingPassengerColor = incomingPassengerCount == null
        ? const Color(0xFF94A3B8)
        : incomingPassengerCount >= 40
            ? const Color(0xFFE53E3E)
            : incomingPassengerCount >= 37
                ? const Color(0xFFD69E2E)
                : const Color(0xFF48BB78);

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
                            Icon(
                              _ridingBusMac == null
                                  ? Icons.directions_bus_rounded
                                  : Icons.flag_rounded,
                              color: _ridingBusMac == null
                                  ? Colors.blue
                                  : const Color(0xFF0F766E),
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                shouldShowOfflineState
                                    ? (offlineBus?.busName ?? 'Bus Offline')
                                    : _ridingBusMac == null
                                        ? (displayBus?.bus.busName ??
                                            'Incoming Bus')
                                        : (nextStop?.stopName ??
                                            'End of route'),
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
                        Text(
                          shouldShowOfflineState
                              ? 'Offline'
                              : _ridingBusMac == null
                                  ? 'Incoming Bus'
                                  : 'Next Station',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (shouldShowOfflineState || _ridingBusMac == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
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
                              Icon(
                                shouldShowOfflineState
                                    ? Icons.cloud_off_rounded
                                    : Icons.people_alt_rounded,
                                size: 16,
                                color: shouldShowOfflineState
                                    ? const Color(0xFF94A3B8)
                                    : incomingPassengerColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                shouldShowOfflineState
                                    ? 'OFFLINE'
                                    : incomingPassengerLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: shouldShowOfflineState
                                      ? const Color(0xFF94A3B8)
                                      : incomingPassengerColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            shouldShowOfflineState ? 'Status' : 'Passenger',
                            style: const TextStyle(
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
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _ridingBusMac == null
                                ? 'INCOMING BUS'
                                : 'NEXT STOP',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0AEC0),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shouldShowOfflineState
                                ? 'Offline'
                                : _ridingBusMac == null
                                    ? (displayBus?.bus.busName ?? '-')
                                    : (nextStop?.stopName ?? '-'),
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
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _ridingBusMac == null
                                ? 'NEXT STATION'
                                : 'PASSENGERS',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0AEC0),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _ridingBusMac == null
                                ? (displayBusArrival?.nextStop?.stopName ?? '-')
                                : (actionBus != null
                                    ? (actionBus.personCount == null
                                        ? '--/40'
                                        : '${actionBus.personCount}/40')
                                    : '-'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748),
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Container(
                        width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'ETA',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0AEC0),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shouldShowOfflineState
                                ? '-'
                                : _ridingBusMac == null
                                    ? (displayBusArrival != null
                                        ? '${displayBusArrival.etaMinutes} min'
                                        : '-')
                                    : (nextStop?.etaMinutes != null
                                        ? '${nextStop!.etaMinutes} min'
                                        : '-'),
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
              if (!shouldShowOfflineState &&
                  _ridingBusMac == null &&
                  incomingBuses.length > 1 &&
                  displayBus != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_bus_filled_rounded,
                          size: 16, color: Color(0xFFA0AEC0)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          incomingBuses
                              .where((bus) =>
                                  bus.bus.busMac != displayBus.bus.busMac)
                              .take(1)
                              .map(
                                (bus) =>
                                    '${bus.bus.busName} in ${bus.etaMinutes} min',
                              )
                              .join(', '),
                          style: const TextStyle(
                            color: Color(0xFFA0AEC0),
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (shouldShowOfflineState)
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE2E8F0),
                      foregroundColor: const Color(0xFF94A3B8),
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'OFFLINE',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_ridingBusMac != null)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _isStartingRide ? null : _cancelRide,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4A5568),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'CANCEL RIDE',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: Builder(
                          builder: (context) {
                            final canRing = actionBus != null &&
                                _activeRideSessionId != null &&
                                _isRingBellAvailable &&
                                !_isRingingBell;

                            return ElevatedButton(
                              onPressed:
                                  canRing ? () => _ringBus(actionBus) : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canRing
                                    ? const Color(0xFFF6C852)
                                    : const Color(0xFFE2E8F0),
                                foregroundColor: canRing
                                    ? Colors.black
                                    : const Color(0xFF94A3B8),
                                disabledBackgroundColor:
                                    const Color(0xFFE2E8F0),
                                disabledForegroundColor:
                                    const Color(0xFF94A3B8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isRingingBell
                                        ? Icons.hourglass_top_rounded
                                        : _isRingBellAvailable
                                            ? Icons.notifications_active_rounded
                                            : Icons.cloud_off_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isRingingBell
                                        ? 'SENDING...'
                                        : _isRingBellAvailable
                                            ? 'RING'
                                            : 'OFFLINE',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isStartingRide
                        ? null
                        : displayBus == null
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No nearby buses available.'),
                                  ),
                                );
                              }
                            : canRide
                                ? () => _startRide(displayBus)
                                : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canRide
                          ? const Color(0xFFF6C852)
                          : const Color(0xFFE2E8F0),
                      foregroundColor:
                          canRide ? Colors.black : const Color(0xFF94A3B8),
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          rideButtonIcon,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          rideButtonLabel,
                          style: const TextStyle(
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
      final route = _resolveRouteForBus(bus, allRoutes);
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

  IncomingBus? findClosestBusForStop(
      Waypoint nearbyStop, List<Bus> buses, List<BusRoute> allRoutes) {
    const avgBusSpeedMs = 25 * 1000 / 3600;
    IncomingBus? closest;

    for (final bus in buses) {
      if (bus.currentLat == null || bus.currentLon == null) continue;
      final route = _resolveRouteForBus(bus, allRoutes);
      if (route == null) continue;

      final distanceM = getDistanceFromLatLonInM(
        bus.currentLat!,
        bus.currentLon!,
        nearbyStop.latitude,
        nearbyStop.longitude,
      ).round();
      final etaMinutes = (distanceM / avgBusSpeedMs / 60).round().clamp(1, 999);
      final candidate = IncomingBus(
        bus: bus,
        routeName: route.routeName,
        routeColor: route.routeColor,
        distanceM: distanceM,
        etaMinutes: etaMinutes,
        stopsAway: 0,
      );

      if (closest == null || candidate.distanceM < closest.distanceM) {
        closest = candidate;
      }
    }

    return closest;
  }

  IncomingBus? findClosestBusToUser(
      LatLng userLocation, List<Bus> buses, List<BusRoute> allRoutes) {
    const avgBusSpeedMs = 25 * 1000 / 3600;
    IncomingBus? closest;

    for (final bus in buses) {
      if (bus.currentLat == null || bus.currentLon == null) continue;

      final distanceM = getDistanceFromLatLonInM(
        userLocation.latitude,
        userLocation.longitude,
        bus.currentLat!,
        bus.currentLon!,
      ).round();
      final etaMinutes = (distanceM / avgBusSpeedMs / 60).round().clamp(1, 999);
      final route = _resolveRouteForBus(bus, allRoutes);

      final candidate = IncomingBus(
        bus: bus,
        routeName: route?.routeName ?? 'Unknown Route',
        routeColor: route?.routeColor ?? '#FF9800',
        distanceM: distanceM,
        etaMinutes: etaMinutes,
        stopsAway: 0,
      );

      if (closest == null || candidate.distanceM < closest.distanceM) {
        closest = candidate;
      }
    }

    return closest;
  }

  Bus? _resolveFocusedBus(List<Bus> buses, List<BusRoute> routes) {
    if (_ridingBusMac != null) {
      final ridingBus =
          buses.where((bus) => bus.busMac == _ridingBusMac).firstOrNull;
      if (ridingBus != null) {
        return ridingBus;
      }
    }

    if (_activeBusMac != null) {
      final activeBus =
          buses.where((bus) => bus.busMac == _activeBusMac).firstOrNull;
      if (activeBus != null) {
        return activeBus;
      }
    }

    if (_userLocation == null) {
      return null;
    }

    return findClosestBusToUser(
      LatLng(_userLocation!.latitude, _userLocation!.longitude),
      buses.where((bus) => !bus.isDebugBus).toList(),
      routes,
    )?.bus;
  }

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busesProvider);
    final routes = ref.watch(routesProvider);
    final developerSettings = ref.watch(developerSettingsProvider);
    final debugMode = ref.watch(debugProvider).debugMode;
    final isDark = ref.watch(themeProvider).isDark;
    final testMode = ref.watch(testModeProvider);
    _syncAnimatedBusPositions(buses, routes);
    final renderedBuses = buses.map(_renderedBus).toList();
    final visibleRenderedBuses =
        renderedBuses.where((bus) => debugMode || !bus.isDebugBus).toList();
    final displayedBuses = _ridingBusMac == null
        ? visibleRenderedBuses
        : visibleRenderedBuses
            .where((bus) => bus.busMac == _ridingBusMac)
            .toList();
    final focusedBus = _resolveFocusedBus(visibleRenderedBuses, routes);
    final focusedRoute = focusedBus != null
        ? _resolveRouteForBus(focusedBus, routes)
        : _activeRoute;
    final focusedStopIndex = focusedRoute != null &&
            focusedBus?.currentLat != null &&
            focusedBus?.currentLon != null
        ? calculateNextStopIndex(
            focusedRoute,
            LatLng(focusedBus!.currentLat!, focusedBus.currentLon!),
            bus: focusedBus,
          )
        : (_activeRoute != null ? _currentStopIndex : null);

    IncomingBus? nearbyBusForRide;
    if (_userLocation != null && routes.isNotEmpty) {
      nearbyBusForRide = findClosestBusToUser(
        LatLng(_userLocation!.latitude, _userLocation!.longitude),
        visibleRenderedBuses.where((bus) => !bus.isOffline).toList(),
        routes,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRideReadyCandidate(nearbyBusForRide);
      _maybeSyncNoGpsAssignedBus(
        buses: visibleRenderedBuses,
        noGpsModeEnabled: developerSettings.noGpsModeEnabled,
      );
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          FlutterMap(
            key: _mapViewportKey,
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _sutCenter,
              initialZoom: 15.5,
              onTap: (tapPosition, point) {
                if (_selectedInfoBusMac != null ||
                    _activeBusMac != null ||
                    _selectedStopKey != null) {
                  _clearSelectedBusFocus();
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
              PolylineLayer(
                polylines: _buildRoutePolylines(
                  routes,
                  focusedRoute: focusedRoute,
                  focusedBus: focusedBus,
                ),
              ),
              MarkerLayer(markers: [
                if (_userLocation != null && _ridingBusMac == null)
                  Marker(
                    point: LatLng(
                        _userLocation!.latitude, _userLocation!.longitude),
                    width: 40,
                    height: 40,
                    child: _buildUserMarker(testMode.enabled),
                  ),
                ..._buildStopMarkers(
                  routes,
                  focusedRoute: focusedRoute,
                  nextStopIndex: focusedStopIndex,
                ),
                ..._buildBusMarkers(
                  displayedBuses,
                  routes,
                ),
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
                _buildModernActionBtn(Icons.my_location, () {
                  if (_userLocation != null) {
                    _mapController.move(
                        LatLng(
                            _userLocation!.latitude, _userLocation!.longitude),
                        17.0);
                  } else {
                    _initLocation();
                  }
                }),
                _buildModernActionBtn(
                  Icons.bar_chart_rounded,
                  () => context.pushNamed('passengerStats'),
                  color: const Color(0xFF0F766E),
                ),
              ],
            ),
          ),
          _buildSelectedBusOverlay(visibleRenderedBuses, routes),
          if (_selectedInfoBusMac == null)
            _buildNearbyPanel(routes, visibleRenderedBuses),
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
