import 'dart:math';
import '../models/waypoint.dart';
import 'map_utils.dart';

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

NextStopResult? findNextStop(
    double? busLat, double? busLon, List<Waypoint> waypoints,
    {double averageSpeedMps = 8.33}) {
  if (waypoints.isEmpty || busLat == null || busLon == null) return null;

  final currentIndex = findClosestWaypointIndex(busLat, busLon, waypoints);

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

  for (int i = 0; i < currentIndex; i++) {
    final wp = waypoints[i];
    if (wp.isStop) {
      return NextStopResult(
        stopName: wp.stopName ?? 'Stop ${i + 1}',
        stopIndex: i,
        distanceM: null,
        etaMinutes: null,
      );
    }
  }

  return null;
}

List<Waypoint> getStopsFromRoute(List<Waypoint> waypoints) {
  return waypoints.where((wp) => wp.isStop).toList();
}
