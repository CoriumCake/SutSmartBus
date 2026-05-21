import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sut_smart_bus/models/bus.dart';
import 'package:sut_smart_bus/utils/no_gps_bus_location.dart';

void main() {
  group('applyNoGpsAssignedBusLocation', () {
    test('moves only the assigned bus to the user location', () {
      final buses = [
        Bus(
          id: 'a',
          busMac: 'BUS-A',
          busName: 'Bus A',
          currentLat: 14,
          currentLon: 102,
          lastUpdated: 1,
        ),
        Bus(
          id: 'b',
          busMac: 'BUS-B',
          busName: 'Bus B',
          currentLat: 15,
          currentLon: 103,
          lastUpdated: 1,
        ),
      ];

      final updated = applyNoGpsAssignedBusLocation(
        buses: buses,
        noGpsModeEnabled: true,
        assignedBusMac: 'BUS-B',
        userLocation: const LatLng(14.88, 102.02),
        lastUpdated: 42,
      );

      expect(updated[0].currentLat, 14);
      expect(updated[0].currentLon, 102);
      expect(updated[1].currentLat, 14.88);
      expect(updated[1].currentLon, 102.02);
      expect(updated[1].isOnline, isTrue);
      expect(updated[1].lastUpdated, 42);
    });

    test('leaves buses unchanged when no GPS mode is disabled', () {
      final buses = [
        Bus(
          id: 'a',
          busMac: 'BUS-A',
          busName: 'Bus A',
          currentLat: 14,
          currentLon: 102,
        ),
      ];

      final updated = applyNoGpsAssignedBusLocation(
        buses: buses,
        noGpsModeEnabled: false,
        assignedBusMac: 'BUS-A',
        userLocation: const LatLng(14.88, 102.02),
      );

      expect(identical(updated, buses), isTrue);
    });
  });
}
