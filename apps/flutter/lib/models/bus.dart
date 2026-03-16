class Bus {
  final String id;
  final String busMac;
  final String? macAddress;
  final String busName;
  final double? currentLat;
  final double? currentLon;
  final int? seatsAvailable;
  final double? pm25;
  final double? pm10;
  final double? temp;
  final double? hum;
  final int? rssi;
  final bool? isOnline;
  final int lastUpdated; // Unix timestamp in milliseconds
  final String? routeId;
  final bool isFake;

  Bus({
    required this.id,
    required this.busMac,
    this.macAddress,
    required this.busName,
    this.currentLat,
    this.currentLon,
    this.seatsAvailable,
    this.pm25,
    this.pm10,
    this.temp,
    this.hum,
    this.rssi,
    this.isOnline,
    this.lastUpdated = 0,
    this.routeId,
    this.isFake = false,
  });

  bool get isOffline => (DateTime.now().millisecondsSinceEpoch - lastUpdated) > 60000;

  factory Bus.fromJson(Map<String, dynamic> json) {
    int timeVal = 0;
    if (json['last_updated'] != null) {
      try {
        String dateStr = json['last_updated'].toString();
        // Handle ISO8601 strings from server
        final dt = DateTime.parse(dateStr);
        timeVal = dt.millisecondsSinceEpoch;
      } catch (e) {
        timeVal = 0;
      }
    }

    // Server uses mac_address as the primary key for devices
    final mac = json['mac_address'] ?? json['bus_mac'] ?? json['id']?.toString() ?? '';

    return Bus(
      id: mac,
      busMac: mac,
      macAddress: json['mac_address'],
      busName: json['bus_name'] ?? 'Bus-${mac.length >= 4 ? mac.substring(mac.length - 4) : mac}',
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLon: (json['current_lon'] as num?)?.toDouble(),
      seatsAvailable: json['seats_available'] as int?,
      pm25: (json['pm2_5'] as num?)?.toDouble(),
      pm10: (json['pm10'] as num?)?.toDouble(),
      temp: (json['temp'] as num?)?.toDouble(),
      hum: (json['hum'] as num?)?.toDouble(),
      rssi: json['rssi'] as int?,
      lastUpdated: timeVal,
      routeId: json['route_id']?.toString(),
    );
  }

  Bus copyWith({
    String? busName,
    double? currentLat,
    double? currentLon,
    int? seatsAvailable,
    double? pm25,
    double? pm10,
    double? temp,
    double? hum,
    int? rssi,
    bool? isOnline,
    int? lastUpdated,
    String? routeId,
  }) {
    return Bus(
      id: id,
      busMac: busMac,
      macAddress: macAddress,
      busName: busName ?? this.busName,
      currentLat: currentLat ?? this.currentLat,
      currentLon: currentLon ?? this.currentLon,
      seatsAvailable: seatsAvailable ?? this.seatsAvailable,
      pm25: pm25 ?? this.pm25,
      pm10: pm10 ?? this.pm10,
      temp: temp ?? this.temp,
      hum: hum ?? this.hum,
      rssi: rssi ?? this.rssi,
      isOnline: isOnline ?? this.isOnline,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      routeId: routeId ?? this.routeId,
      isFake: isFake,
    );
  }
}
