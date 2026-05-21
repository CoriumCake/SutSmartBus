import 'package:latlong2/latlong.dart';

import '../models/bus.dart';

bool isNoGpsAssignedBus(
  Bus bus, {
  required bool noGpsModeEnabled,
  required String? assignedBusMac,
}) {
  final normalizedAssignedBusMac = assignedBusMac?.trim();
  return noGpsModeEnabled &&
      normalizedAssignedBusMac != null &&
      normalizedAssignedBusMac.isNotEmpty &&
      bus.busMac == normalizedAssignedBusMac;
}

List<Bus> applyNoGpsAssignedBusLocation({
  required List<Bus> buses,
  required bool noGpsModeEnabled,
  required String? assignedBusMac,
  required LatLng? userLocation,
  int? lastUpdated,
}) {
  final normalizedAssignedBusMac = assignedBusMac?.trim();
  if (!noGpsModeEnabled ||
      normalizedAssignedBusMac == null ||
      normalizedAssignedBusMac.isEmpty ||
      userLocation == null) {
    return buses;
  }

  var foundAssignedBus = false;
  final updatedAt = lastUpdated ?? DateTime.now().millisecondsSinceEpoch;
  final updatedBuses = buses.map((bus) {
    if (bus.busMac != normalizedAssignedBusMac) {
      return bus;
    }

    foundAssignedBus = true;
    return bus.copyWith(
      currentLat: userLocation.latitude,
      currentLon: userLocation.longitude,
      isOnline: true,
      lastUpdated: updatedAt,
    );
  }).toList(growable: false);

  return foundAssignedBus ? updatedBuses : buses;
}
