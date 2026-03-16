class Waypoint {
  final double latitude;
  final double longitude;
  final bool isStop;
  final String? stopName;

  Waypoint({
    required this.latitude,
    required this.longitude,
    this.isStop = false,
    this.stopName,
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      latitude: (json['latitude'] ?? json['lat'] as num).toDouble(),
      longitude: (json['longitude'] ?? json['lon'] as num).toDouble(),
      isStop: json['isStop'] ?? (json['name'] != null), // If it has a name, it's likely a stop
      stopName: json['stopName'] ?? json['name'],
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'isStop': isStop,
    'stopName': stopName,
  };
}
