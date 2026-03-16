# 12 — Testing Strategy

## Purpose
Define a comprehensive testing strategy for the Flutter app, covering unit tests, widget tests, and integration tests.

## Reference
- Original RN test setup: `apps/mobile/__tests__/` (Jest + React Native Testing Library)

---

## Testing Stack

| Tool | Purpose |
|---|---|
| `flutter_test` | Unit + Widget tests (built-in) |
| `mockito` | Mocking services (API, MQTT) |
| `integration_test` | Full-app integration tests |
| `patrol` (optional) | Native UI testing on real devices |

---

## Test Directory Structure

```
test/
├── unit/
│   ├── models/
│   │   ├── bus_test.dart
│   │   ├── route_model_test.dart
│   │   └── waypoint_test.dart
│   ├── utils/
│   │   ├── map_utils_test.dart
│   │   ├── route_helpers_test.dart
│   │   └── air_quality_utils_test.dart
│   └── services/
│       ├── api_service_test.dart
│       └── route_storage_service_test.dart
├── widget/
│   ├── bus_card_test.dart
│   ├── settings_screen_test.dart
│   └── about_screen_test.dart
└── integration/
    └── app_test.dart
```

---

## 1. Unit Tests

### `test/unit/models/bus_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/models/bus.dart';

void main() {
  group('Bus model', () {
    test('fromJson creates bus with correct fields', () {
      final json = {
        'bus_mac': 'AA:BB:CC:DD:EE:FF',
        'bus_name': 'SUT-Bus-01',
        'current_lat': 14.882,
        'current_lon': 102.021,
        'pm2_5': 23.5,
        'pm10': 31.2,
        'temp': 28.5,
        'hum': 65.0,
        'seats_available': 15,
        'last_updated': '2025-01-01T12:00:00Z',
      };

      final bus = Bus.fromJson(json);

      expect(bus.busMac, 'AA:BB:CC:DD:EE:FF');
      expect(bus.busName, 'SUT-Bus-01');
      expect(bus.currentLat, 14.882);
      expect(bus.currentLon, 102.021);
      expect(bus.pm25, 23.5);
      expect(bus.pm10, 31.2);
    });

    test('fromJson handles timestamp without timezone', () {
      final json = {
        'bus_mac': 'AA:BB:CC:DD:EE:FF',
        'last_updated': '2025-01-01 12:00:00',
      };

      final bus = Bus.fromJson(json);
      expect(bus.lastUpdated, greaterThan(0));
    });

    test('isOffline returns true if lastUpdated > 60s ago', () {
      final bus = Bus(
        id: '1', busMac: 'AA:BB:CC:DD:EE:FF', busName: 'Test',
        lastUpdated: DateTime.now().millisecondsSinceEpoch - 120000,
      );
      expect(bus.isOffline, true);
    });

    test('isOffline returns false if lastUpdated < 60s ago', () {
      final bus = Bus(
        id: '1', busMac: 'AA:BB:CC:DD:EE:FF', busName: 'Test',
        lastUpdated: DateTime.now().millisecondsSinceEpoch - 30000,
      );
      expect(bus.isOffline, false);
    });

    test('copyWith preserves unchanged fields', () {
      final bus = Bus(
        id: '1', busMac: 'AA:BB:CC:DD:EE:FF', busName: 'Original',
        currentLat: 14.0, currentLon: 102.0,
      );
      final updated = bus.copyWith(busName: 'Updated');
      expect(updated.busName, 'Updated');
      expect(updated.currentLat, 14.0);
      expect(updated.busMac, 'AA:BB:CC:DD:EE:FF');
    });

    test('fromJson generates name from MAC when no bus_name', () {
      final bus = Bus.fromJson({'bus_mac': 'AA:BB:CC:DD:EE:FF'});
      expect(bus.busName, contains('E:FF'));
    });
  });
}
```

### `test/unit/utils/map_utils_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/utils/map_utils.dart';

void main() {
  group('Haversine distance', () {
    test('same point returns 0', () {
      expect(getDistanceFromLatLonInM(14.882, 102.021, 14.882, 102.021), closeTo(0, 1));
    });

    test('SUT campus gate to center is ~1-2km', () {
      final dist = getDistanceFromLatLonInM(14.882, 102.021, 14.871, 102.015);
      expect(dist, greaterThan(500));
      expect(dist, lessThan(2500));
    });
  });

  group('Polyline simplification', () {
    test('returns same points if fewer than 3', () {
      final points = [
        (latitude: 14.0, longitude: 102.0),
        (latitude: 14.1, longitude: 102.1),
      ];
      expect(simplifyPolyline(points).length, 2);
    });

    test('removes collinear points', () {
      final points = [
        (latitude: 0.0, longitude: 0.0),
        (latitude: 0.5, longitude: 0.5),
        (latitude: 1.0, longitude: 1.0),
      ];
      final simplified = simplifyPolyline(points, tolerance: 0.01);
      expect(simplified.length, 2);
    });
  });
}
```

### `test/unit/utils/air_quality_utils_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/utils/air_quality_utils.dart';

void main() {
  group('getAirQualityStatus', () {
    test('null returns No Data', () {
      expect(getAirQualityStatus(null).label, 'No Data');
    });
    test('PM2.5 <= 25 returns Good', () {
      expect(getAirQualityStatus(20).label, 'Good');
    });
    test('PM2.5 25-50 returns Moderate', () {
      expect(getAirQualityStatus(35).label, 'Moderate');
    });
    test('PM2.5 50-75 returns Unhealthy (Sensitive)', () {
      expect(getAirQualityStatus(60).label, 'Unhealthy (Sensitive)');
    });
    test('PM2.5 > 75 returns Unhealthy', () {
      expect(getAirQualityStatus(100).label, 'Unhealthy');
    });
  });
}
```

### `test/unit/utils/route_helpers_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/utils/route_helpers.dart';
import 'package:sut_smart_bus/models/waypoint.dart';

void main() {
  group('findClosestWaypointIndex', () {
    test('returns -1 for empty list', () {
      expect(findClosestWaypointIndex(14.0, 102.0, []), -1);
    });

    test('finds closest waypoint', () {
      final waypoints = [
        Waypoint(latitude: 14.0, longitude: 102.0),     // index 0
        Waypoint(latitude: 14.1, longitude: 102.1),     // index 1
        Waypoint(latitude: 14.882, longitude: 102.021), // index 2 (SUT)
      ];
      expect(findClosestWaypointIndex(14.88, 102.02, waypoints), 2);
    });
  });

  group('findNextStop', () {
    test('returns null for empty waypoints', () {
      expect(findNextStop(14.0, 102.0, []), null);
    });

    test('returns null for null coordinates', () {
      expect(findNextStop(null, null, [
        Waypoint(latitude: 14.0, longitude: 102.0, isStop: true, stopName: 'A'),
      ]), null);
    });

    test('finds next stop ahead of bus', () {
      final waypoints = [
        Waypoint(latitude: 14.0, longitude: 102.0),
        Waypoint(latitude: 14.1, longitude: 102.0, isStop: true, stopName: 'Stop A'),
        Waypoint(latitude: 14.2, longitude: 102.0, isStop: true, stopName: 'Stop B'),
      ];
      final result = findNextStop(14.05, 102.0, waypoints);
      expect(result?.stopName, 'Stop A');
    });
  });

  group('getStopsFromRoute', () {
    test('filters only stop waypoints', () {
      final waypoints = [
        Waypoint(latitude: 14.0, longitude: 102.0),
        Waypoint(latitude: 14.1, longitude: 102.0, isStop: true, stopName: 'A'),
        Waypoint(latitude: 14.2, longitude: 102.0),
        Waypoint(latitude: 14.3, longitude: 102.0, isStop: true, stopName: 'B'),
      ];
      expect(getStopsFromRoute(waypoints).length, 2);
    });
  });
}
```

---

## 2. Widget Tests

### `test/widget/about_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/screens/about_screen.dart';

void main() {
  testWidgets('AboutScreen renders app name and version', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AboutScreen()),
      ),
    );

    expect(find.text('SUT Smart Bus'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsOneWidget);
    expect(find.text('Development Team'), findsOneWidget);
  });
}
```

---

## 3. Running Tests

### Commands

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/unit/models/bus_test.dart

# Run with coverage
flutter test --coverage

# Run integration tests (requires device/emulator)
flutter test integration_test/app_test.dart
```

---

## Verification Checklist

- [ ] `flutter test` runs all unit tests and passes
- [ ] Bus model tests verify JSON parsing, timestamp handling, offline detection
- [ ] Map utils tests verify distance calculation and polyline simplification
- [ ] Air quality utils tests verify all threshold categories
- [ ] Route helper tests verify stop finding and closest waypoint
- [ ] Widget tests verify screen rendering
- [ ] Test coverage report generates via `--coverage`
