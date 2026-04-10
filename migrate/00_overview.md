# 00 — Flutter Migration Master Plan

## Overview

This folder contains a step-by-step plan to migrate the **SUT Smart Bus** mobile app from **React Native (Expo SDK 54, JavaScript)** to **Flutter (Dart)**. The backend server (Python/FastAPI) and hardware layer (ESP32) remain **unchanged**.

---

## Current Tech Stack

| Layer | Current Technology |
|---|---|
| Framework | React Native 0.81.5 + Expo SDK 54 |
| Language | JavaScript (ES6+) |
| Navigation | React Navigation 6 (Bottom Tabs + Stack) |
| State | React Context API (5 providers) |
| Maps | `react-native-maps` (Google Maps) |
| Real-time | MQTT via `mqtt` npm (WebSocket) |
| HTTP | `axios` |
| Storage | `@react-native-async-storage/async-storage` |
| Notifications | `expo-notifications` |
| Location | `expo-location` |
| Icons | `@expo/vector-icons` (Ionicons, MaterialCommunityIcons) |

## Target Tech Stack

| Layer | Flutter Equivalent |
|---|---|
| Framework | Flutter 3.x |
| Language | Dart 3.x |
| Navigation | `go_router` |
| State | `flutter_riverpod` |
| Maps | `flutter_map` | Leaflet/OSM based |
| Real-time | `mqtt_client` (WebSocket) |
| HTTP | `dio` |
| Storage | `shared_preferences` + `hive` |
| Notifications | `flutter_local_notifications` |
| Location | `geolocator` + `geocoding` |
| Icons | `material_design_icons_flutter` + built-in Material Icons |

---

## Execution Order

> **Each document is self-contained** and can be executed independently by an agent. Follow this order for the smoothest migration:

```
Phase 1: Foundation
├── 01_project_setup.md      ← Create Flutter project, add dependencies
├── 02_architecture.md       ← Set up folder structure & state management
├── 03_theming.md            ← Theme system, colors, typography, dark mode

Phase 2: Core Infrastructure
├── 04_navigation.md         ← Bottom tabs + stack navigation
├── 05_data_layer.md         ← API client, MQTT service, data models

Phase 3: Screen Migration (order matters)
├── 06_map_screen.md         ← Map screen (most complex, ~3035 lines)
├── 07_routes_screen.md      ← Routes list screen
├── 08_air_quality_screen.md ← Air quality (map + list hybrid)
├── 09_settings_screen.md    ← Settings & preferences
├── 10_admin_screens.md      ← Bus Management, Route Admin, Route Editor, AQ Dashboard, About

Phase 4: Polish
├── 11_utilities.md          ← Utility functions migration
├── 12_testing.md            ← Testing strategy & test files
├── 13_deployment.md         ← Build, signing, deployment
```

---

## Dependency Graph Between Documents

```
01_project_setup
    └── 02_architecture
        ├── 03_theming
        └── 04_navigation
            └── 05_data_layer
                ├── 11_utilities (can be done in parallel with screens)
                ├── 06_map_screen
                ├── 07_routes_screen
                ├── 08_air_quality_screen
                ├── 09_settings_screen
                └── 10_admin_screens
                    └── 12_testing
                        └── 13_deployment
```

---

## Key Package Mapping (React Native → Flutter)

| React Native Package | Flutter Package | Notes |
|---|---|---|
| `react-native-maps` | `flutter_map` | Leaflet/OSM based |
| `mqtt` (npm) | `mqtt_client` | Different API but same MQTT 3.1.1 |
| `axios` | `dio` | Interceptors, timeouts, etc. |
| `@react-native-async-storage/async-storage` | `shared_preferences` | For simple key-value |
| `@react-native-async-storage/async-storage` | `hive` | For complex objects (routes) |
| `expo-location` | `geolocator` | Permission handling differs |
| `expo-notifications` | `flutter_local_notifications` | Setup is more manual in Flutter |
| `@react-navigation/bottom-tabs` | `go_router` + `NavigationBar` | Built-in Material widget |
| `@react-navigation/stack` | `go_router` | Declarative routing |
| `react-native-gesture-handler` | Built-in | Flutter has gestures built in |
| `react-native-reanimated` | Built-in | Flutter animations are native |
| `@expo/vector-icons` (Ionicons) | `material_design_icons_flutter` | Or use built-in Material Icons |
| `react-native-safe-area-context` | `SafeArea` widget | Built into Flutter |
| `@react-native-picker/picker` | `DropdownButton` | Built-in widget |
| `expo-secure-store` | `flutter_secure_storage` | For sensitive data |
| `expo-application` | `device_info_plus` | Device identification |

---

## File Count Summary

| Category | React Native Files | Flutter Files (estimated) |
|---|---|---|
| Screens | 12 | 12 |
| Components | 6 | 8-10 (smaller widgets) |
| Contexts → Providers | 5 | 5 (Riverpod providers) |
| Utils | 7 | 7 |
| Config | 3 | 2-3 |
| Models | 0 (inline) | 5-6 (typed Dart classes) |
| Services | 0 (inline) | 3-4 (API, MQTT, storage) |
| **Total** | ~33 | ~45-50 |

---

## Important Notes

1. **The backend API is untouched.** All endpoints (`/api/buses`, `/api/routes`, `/api/routes/{id}/stops`, etc.) stay exactly the same.
2. **MQTT topics remain identical:** `sut/app/bus/location`, `sut/bus/gps/fast`, `sut/bus/gps`, `sut/person-detection`, `sut/bus/+/status`.
3. **The Flutter app will live in `apps/flutter/` alongside the existing `apps/mobile/`** so both can coexist during migration.
4. **Google Maps API key** from the React Native project can be reused for Flutter.
5. **Each migration document includes**: purpose, source files being migrated, exact Dart code structure, package dependencies, and verification steps.
