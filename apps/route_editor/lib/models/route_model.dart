import 'waypoint.dart';

class BusRoute {
  final String routeId;
  final String routeName;
  final List<Waypoint> waypoints;
  final String routeColor;
  final String? createdAt;
  final String? updatedAt;

  BusRoute({
    required this.routeId,
    required this.routeName,
    required this.waypoints,
    this.routeColor = '#2563eb',
    this.createdAt,
    this.updatedAt,
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      routeId: (json['id'] ?? json['routeId'] ?? json['route_id'] ?? '')
          .toString(),
      routeName:
          json['name'] ??
          json['routeName'] ??
          json['route_name'] ??
          'Unnamed Route',
      waypoints:
          (json['waypoints'] as List<dynamic>?)
              ?.map((w) => Waypoint.fromJson(w))
              .toList() ??
          [],
      routeColor: json['routeColor'] ?? json['route_color'] ?? '#2563eb',
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() => {
    'routeId': routeId,
    'routeName': routeName,
    'waypoints': waypoints.map((w) => w.toJson()).toList(),
    'routeColor': routeColor,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  List<Waypoint> get stops =>
      waypoints.where((w) => w.isStop && w.stopName != null).toList();
}
