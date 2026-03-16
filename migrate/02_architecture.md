# 02 — App Architecture & State Management

## Purpose
Define the Flutter app's folder structure, state management pattern (Riverpod), and core data models that replace the React Context API.

## Source Files Being Replaced
- `contexts/DataContext.js` → `lib/providers/data_provider.dart`
- `contexts/ThemeContext.js` → `lib/providers/theme_provider.dart`
- `contexts/LanguageContext.js` → `lib/providers/language_provider.dart`
- `contexts/DebugContext.js` → `lib/providers/debug_provider.dart`
- `contexts/NotificationContext.js` → `lib/providers/notification_provider.dart`

---

## Folder Structure

```
lib/
├── main.dart                      # App entry point
├── app.dart                       # MaterialApp + GoRouter setup
├── config/
│   ├── api_config.dart            # API_BASE, MQTT_CONFIG equivalent
│   ├── env.dart                   # Environment variables
│   └── allowed_devices.dart       # Device allowlist for debug mode
├── models/
│   ├── bus.dart                   # Bus data model
│   ├── route_model.dart           # Route data model (with waypoints)
│   ├── waypoint.dart              # Waypoint model (lat, lng, isStop, stopName)
│   ├── air_quality.dart           # AQ status model
│   └── bus_route_mapping.dart     # Bus-to-route mapping model
├── providers/
│   ├── data_provider.dart         # Buses + Routes state (replaces DataContext)
│   ├── theme_provider.dart        # Dark/Light mode (replaces ThemeContext)
│   ├── language_provider.dart     # i18n (replaces LanguageContext)
│   ├── debug_provider.dart        # Debug mode (replaces DebugContext)
│   └── notification_provider.dart # Notifications (replaces NotificationContext)
├── services/
│   ├── api_service.dart           # HTTP client (Dio-based)
│   ├── mqtt_service.dart          # MQTT client wrapper
│   ├── route_storage_service.dart # Local route storage (Hive)
│   ├── bus_mapping_service.dart   # Bus↔Route mapping
│   └── location_service.dart      # GPS location service
├── screens/
│   ├── map_screen.dart
│   ├── routes_screen.dart
│   ├── air_quality_screen.dart
│   ├── settings_screen.dart
│   ├── bus_management_screen.dart
│   ├── bus_route_admin_screen.dart
│   ├── route_editor_screen.dart
│   ├── air_quality_dashboard_screen.dart
│   ├── about_screen.dart
│   └── feedback_screen.dart
├── widgets/
│   ├── bus_card.dart              # Reusable bus info card
│   ├── bus_marker.dart            # Animated bus map marker
│   ├── air_quality_map.dart       # AQ heatmap widget
│   ├── grid_overlay.dart          # Map grid overlay
│   ├── stop_marker.dart           # Bus stop marker widget
│   ├── error_boundary.dart        # Error boundary widget
│   └── loading_overlay.dart       # Loading splash widget
├── utils/
│   ├── map_utils.dart             # Haversine, polyline simplification
│   ├── air_quality_utils.dart     # AQ status color/label logic
│   ├── route_helpers.dart         # findNextStop, calculateDistance
│   └── map_styles.dart            # Google Maps JSON styling
└── l10n/
    ├── app_en.dart                # English translations
    └── app_th.dart                # Thai translations
```

---

## Data Models

### `lib/models/bus.dart`

```dart
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
      String dateStr = json['last_updated'].toString();
      if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
        dateStr += 'Z';
      }
      timeVal = DateTime.tryParse(dateStr)?.millisecondsSinceEpoch ?? 0;
    }

    return Bus(
      id: json['id']?.toString() ?? json['bus_mac'] ?? '',
      busMac: json['bus_mac'] ?? json['mac_address'] ?? json['id']?.toString() ?? '',
      macAddress: json['mac_address'],
      busName: json['bus_name'] ?? 'Bus-${(json['bus_mac'] ?? '').toString().substring((json['bus_mac'] ?? '').toString().length - 4)}',
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
```

### `lib/models/waypoint.dart`

```dart
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
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      isStop: json['isStop'] ?? false,
      stopName: json['stopName'],
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'isStop': isStop,
    'stopName': stopName,
  };
}
```

### `lib/models/route_model.dart`

```dart
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
      routeId: json['routeId'] ?? json['id']?.toString() ?? '',
      routeName: json['routeName'] ?? 'Unnamed Route',
      waypoints: (json['waypoints'] as List<dynamic>?)
          ?.map((w) => Waypoint.fromJson(w))
          .toList() ?? [],
      busId: json['busId'],
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
```

---

## Riverpod Providers (replacing React Context)

### Provider Architecture

```
                    ┌─────────────────────────────┐
                    │       ProviderScope          │
                    │       (in main.dart)         │
                    └─────────────┬───────────────┘
                                  │
        ┌─────────┬───────────┬───┴───┬──────────┬────────────┐
        │         │           │       │          │            │
   themeProvider   langProvider  debugProvider  notifProvider  dataProvider
   (StateNotifier) (StateNotifier) (StateNotifier) (StateNotifier) (AsyncNotifier)
                                                                     │
                                                            ┌───────┴────────┐
                                                         apiService    mqttService
```

### `lib/providers/theme_provider.dart` (example)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// See 03_theming.md for full theme definitions

class ThemeState {
  final bool isDark;
  final ThemeData themeData;

  ThemeState({required this.isDark, required this.themeData});
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(ThemeState(isDark: false, themeData: lightThemeData)) {
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme');
    if (savedTheme == 'dark') {
      state = ThemeState(isDark: true, themeData: darkThemeData);
    }
  }

  Future<void> toggleTheme() async {
    final newIsDark = !state.isDark;
    state = ThemeState(
      isDark: newIsDark,
      themeData: newIsDark ? darkThemeData : lightThemeData,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', newIsDark ? 'dark' : 'light');
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});
```

### `lib/main.dart` (entry point)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const ProviderScope(child: SutSmartBusApp()));
}
```

---

## React Context → Riverpod Mapping

| React Context | Riverpod Provider | State Type |
|---|---|---|
| `DataContext` (buses, routes, loading) | `dataProvider` | `AsyncNotifierProvider` |
| `ThemeContext` (isDark, theme, toggleTheme) | `themeProvider` | `StateNotifierProvider<ThemeNotifier, ThemeState>` |
| `LanguageContext` (language, t(), changeLanguage) | `languageProvider` | `StateNotifierProvider<LanguageNotifier, LanguageState>` |
| `DebugContext` (debugMode, isDevMachine) | `debugProvider` | `StateNotifierProvider<DebugNotifier, DebugState>` |
| `NotificationContext` (enabled, send...) | `notificationProvider` | `StateNotifierProvider<NotificationNotifier, NotificationState>` |

---

## Verification Checklist

- [ ] All model classes compile without errors
- [ ] Providers can be instantiated inside a `ProviderScope`
- [ ] `main.dart` launches the app with `ProviderScope` wrapping
- [ ] Hive initializes correctly on app start
- [ ] Folder structure matches the plan above

---

## Notes for Agent

- Do NOT use the Riverpod code generator (`@riverpod` annotation) for now — use manual `StateNotifierProvider` to keep it simple and explicit.
- The `Bus` model's `fromJson` method includes the same timestamp normalization logic from `DataContext.js` (appending 'Z' if no timezone info).
- The `copyWith` pattern on `Bus` supports the smart-merge logic from the React Native `DataContext`.
