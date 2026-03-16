import 'waypoint.dart';

class BusRoute {
  final String routeId;
  final String routeName;
  final List<Waypoint> waypoints;
  final String? busId;
  final String routeColor;
  final String? createdAt;
  final String? updatedAt;

  BusRoute({
    required this.routeId,
    required this.routeName,
    required this.waypoints,
    this.busId,
    this.routeColor = '#2563eb',
    this.createdAt,
    this.updatedAt,
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      routeId: (json['id'] ?? json['routeId'] ?? '').toString(),
      routeName: json['name'] ?? json['routeName'] ?? 'Unnamed Route',
      waypoints: (json['waypoints'] as List<dynamic>?)
          ?.map((w) => Waypoint.fromJson(w))
          .toList() ?? [],
      busId: json['bus_id']?.toString() ?? json['busId']?.toString(),
      routeColor: json['routeColor'] ?? '#2563eb',
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() => {
    'routeId': routeId,
    'routeName': routeName,
    'waypoints': waypoints.map((w) => w.toJson()).toList(),
    'busId': busId,
    'routeColor': routeColor,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  List<Waypoint> get stops => waypoints.where((w) => w.isStop && w.stopName != null).toList();
}
