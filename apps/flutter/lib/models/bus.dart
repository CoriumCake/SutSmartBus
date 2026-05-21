class Bus {
  static const int maxPassengerCount = 40;
  final String id;
  final String? busId;
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
  final int? personCount;

  Bus({
    required this.id,
    this.busId,
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
    this.personCount,
  });

  bool get isOffline =>
      isOnline == false ||
      (DateTime.now().millisecondsSinceEpoch - lastUpdated) > 60000;

  bool get isDebugBus {
    final normalizedName = busName.toUpperCase();
    final normalizedMac = busMac.toUpperCase();
    final normalizedAddress = macAddress?.toUpperCase();

    return isFake ||
        normalizedMac.startsWith('DEBUG-') ||
        normalizedName.contains('DEBUG') ||
        normalizedName.contains('(TEST)') ||
        (normalizedAddress?.startsWith('DEBUG-') ?? false);
  }

  static int _parseLastUpdated(dynamic value) {
    if (value == null) return 0;

    try {
      if (value is int) {
        return value;
      }

      final raw = value.toString().trim();
      if (raw.isEmpty) return 0;

      final numeric = int.tryParse(raw);
      if (numeric != null) {
        return numeric;
      }

      final hasTimezone =
          raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
      final normalized = hasTimezone ? raw : '${raw}Z';

      return DateTime.parse(normalized).millisecondsSinceEpoch;
    } catch (e) {
      return 0;
    }
  }

  static int? _normalizePassengerCount(dynamic value) {
    if (value == null) return null;
    final count = value is num ? value.toInt() : int.tryParse(value.toString());
    if (count == null) return null;
    return count.clamp(0, maxPassengerCount);
  }

  static int? _parsePassengerCount(Map<String, dynamic> json) {
    final count = _normalizePassengerCount(json['person_count']);
    if (count != 0) return count;

    final source = json['count_source']?.toString().toLowerCase();
    return source == 'door' || source == 'developer' ? 0 : null;
  }

  factory Bus.fromJson(Map<String, dynamic> json) {
    final timeVal = _parseLastUpdated(json['last_updated']);

    // Server uses mac_address as the primary key for devices
    final mac =
        json['mac_address'] ?? json['bus_mac'] ?? json['id']?.toString() ?? '';
    final busId = json['bus_id']?.toString().trim();
    final effectiveId = (busId != null && busId.isNotEmpty) ? busId : mac;

    return Bus(
      id: effectiveId,
      busId: busId != null && busId.isNotEmpty ? busId : null,
      busMac: mac,
      macAddress: json['mac_address'],
      busName: json['bus_name'] ??
          'Bus-${mac.length >= 4 ? mac.substring(mac.length - 4) : mac}',
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLon: (json['current_lon'] as num?)?.toDouble(),
      seatsAvailable: json['seats_available'] as int?,
      pm25: (json['pm2_5'] as num?)?.toDouble(),
      pm10: (json['pm10'] as num?)?.toDouble(),
      temp: (json['temp'] as num?)?.toDouble(),
      hum: (json['hum'] as num?)?.toDouble(),
      rssi: (json['rssi'] as num?)?.toInt(),
      lastUpdated: timeVal,
      routeId: json['route_id']?.toString(),
      personCount: _parsePassengerCount(json),
    );
  }

  Bus copyWith({
    String? id,
    String? busId,
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
    int? personCount,
  }) {
    final nextBusId = busId ?? this.busId;
    final nextId = id ??
        ((nextBusId != null && nextBusId.isNotEmpty) ? nextBusId : this.id);
    return Bus(
      id: nextId,
      busId: busId ?? this.busId,
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
      personCount: personCount != null
          ? personCount.clamp(0, maxPassengerCount).toInt()
          : this.personCount,
    );
  }
}
