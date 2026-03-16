import 'dart:math';

double deg2rad(double deg) => deg * (pi / 180);

double getDistanceFromLatLonInM(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0; 
  final dLat = deg2rad(lat2 - lat1);
  final dLon = deg2rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(deg2rad(lat1)) * cos(deg2rad(lat2)) *
      sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c * 1000; 
}

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
