# SutSmartBus Flutter App

Smart transit and environmental monitoring application for Suranaree University of Technology (SUT).

## Project Overview
The `sut_smart_bus` application provides real-time tracking of university shuttle buses and monitors campus air quality (PM2.5, PM10). It integrates with a backend server via HTTP APIs and uses MQTT for real-time location and sensor updates.

### Key Features
- **Real-time Map:** Displays bus locations, routes, and air quality heatmaps.
- **Route Management:** View bus routes and stops.
- **Air Quality Dashboard:** Environmental data visualization.
- **Bus Management:** Admin tools for managing the bus fleet.
- **Developer Mode:** Testing and simulation tools for location and data updates.

## Tech Stack
- **Framework:** Flutter (>=3.24.0)
- **State Management:** Riverpod (`flutter_riverpod`, `riverpod_annotation`)
- **Navigation:** `go_router`
- **Networking:** `dio` (HTTP), `mqtt_client` (Real-time)
- **Maps:** `flutter_map`
- **Storage:** `hive` (Local database), `shared_preferences`
- **Localization:** `intl`

## Project Structure
- `lib/models/`: Data models (Bus, Route, Waypoint).
- `lib/providers/`: State management using Riverpod (Data, Theme, Language, etc.).
- `lib/services/`: Communication logic (API, MQTT, Storage).
- `lib/screens/`: UI screens and pages.
- `lib/widgets/`: Reusable UI components.
- `lib/config/`: Configuration files (Theme, API, Environment).
- `lib/utils/`: Helper functions and styles.

## Building and Running

### Prerequisites
- Flutter SDK installed and configured.
- `lib/config/env.dart` (not tracked in git) should be configured with server details.

### Commands
- **Install dependencies:** `flutter pub get`
- **Run build runner (for code generation):** `flutter pub run build_runner build --delete-conflicting-outputs`
- **Run the app:** `flutter run`
- **Run tests:** `flutter test`

## Development Conventions
- **State Management:** Use Riverpod for all global and local states. Prefer `StateNotifierProvider` or `Provider`.
- **Navigation:** Use `go_router` for all navigation. Define routes in `lib/app.dart`.
- **Models:** Use `fromJson` and `toJson` for serialization.
- **Commits:** Follow conventional commit messages if possible.
- **Linting:** Adhere to rules defined in `analysis_options.yaml`.

## Key Files
- `lib/main.dart`: Entry point of the application.
- `lib/app.dart`: App widget and routing configuration.
- `lib/providers/data_provider.dart`: Core state notifier for bus and route data.
- `lib/services/mqtt_service.dart`: Handles MQTT connection and real-time messaging.
- `lib/services/api_service.dart`: Handles HTTP requests to the backend.
