# Repository Guidelines

## Project Structure & Module Organization
`apps/flutter/` contains the Flutter client. Main app code lives in `lib/` with feature areas such as `screens/`, `providers/`, `services/`, and `widgets/`; tests live in `apps/flutter/test/`; static assets are under `apps/flutter/assets/`.

`server/` contains the FastAPI backend. Core API code is in `server/app/`, shared config and auth helpers are in `server/core/`, route data is stored in `server/routes/`, and operational scripts such as seed and maintenance helpers live beside the app code. `hardware/` holds ESP32 and sensor firmware projects.

## Build, Test, and Development Commands
Use the repo root for containerized backend work:

- `docker-compose up -d --build` starts MongoDB, Mosquitto, and the FastAPI server.
- `docker-compose logs -f` tails service logs.
- `docker-compose down` stops the stack.

Use `apps/flutter/` for mobile development:

- `flutter pub get` installs Dart dependencies.
- `flutter run` launches the app on a connected device or emulator.
- `flutter analyze` runs static analysis from `analysis_options.yaml`.
- `flutter test` runs widget and provider tests.
- `flutter pub run build_runner build --delete-conflicting-outputs` regenerates Riverpod, Hive, and Mockito code.

## Coding Style & Naming Conventions
Follow existing project defaults: 4-space indentation in Python and standard Flutter formatting in Dart. Keep Dart files `snake_case.dart`, classes `PascalCase`, variables and methods `camelCase`. Python modules are also `snake_case.py`. Prefer small, feature-focused files in `lib/` and keep generated `*.mocks.dart` files out of manual edits. Use `flutter analyze` before opening a PR; there is no separate Python formatter configured in this repo.

## Testing Guidelines
Flutter tests live in `apps/flutter/test/` and use `flutter_test` plus `mockito`. Name tests with the `_test.dart` suffix, matching the production feature where possible, for example `test_mode_screen_test.dart`. The backend currently has no committed automated test suite, so backend changes should include at least a local API smoke check against `http://localhost:8000/health` and relevant endpoints.

## Commit & Pull Request Guidelines
Recent history uses short, imperative messages and often follows conventional prefixes such as `feat:`, `fix:`, `chore:`, and `backup:`. Keep commits focused and descriptive, for example `fix: handle offline MQTT reconnect in dashboard`.

Pull requests should include a concise summary, affected areas (`apps/flutter`, `server`, `hardware`), linked issues when applicable, and screenshots or screen recordings for UI changes. Call out config changes to `.env`, Docker, MQTT, or firmware behavior explicitly.
