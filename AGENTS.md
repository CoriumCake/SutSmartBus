# Repository Guidelines

## Project Structure & Module Organization
This repository is split by runtime. `apps/flutter/` contains the production mobile client with source in `lib/`, assets in `assets/`, and tests in `test/`. `server/` holds the FastAPI backend: HTTP routes live in `app/routers/`, shared models and schemas in `app/`, and config/auth helpers in `core/`. `hardware/` contains ESP32 and Arduino firmware. Root `docker-compose.yml` starts MongoDB, Mosquitto, and the API together.

## Build, Test, and Development Commands
Use the command set for the area you are changing.

- `docker-compose up -d --build`: start the backend stack locally.
- `docker-compose logs -f server`: follow API logs.
- `cd apps/flutter && flutter pub get && flutter run`: run the Flutter app.
- `cd apps/flutter && flutter test`: run Flutter tests.
- `cd apps/flutter && flutter analyze`: run Dart static analysis.

## Coding Style & Naming Conventions
Dart files use `snake_case` filenames, `PascalCase` types, and the `flutter_lints` rules from `analysis_options.yaml`. Python modules in `server/` follow `snake_case` and should stay small and router-focused. Prefer descriptive JSON names like `route_*.json`. Keep secrets in local env files copied from `apps/flutter/lib/config/env.dart.example` or `server/.env.example`, never in source.

## Testing Guidelines
Add or update tests with every behavior change. Place Flutter tests in `apps/flutter/test/` using `*_test.dart`. Run the narrowest relevant suite first, then the full Flutter suite before opening a PR.

## Commit & Pull Request Guidelines
Recent history mixes plain summaries with Conventional Commit prefixes; prefer the clearer prefixed style: `feat:`, `fix:`, `chore:`. Keep each commit scoped to one change. Pull requests should include a short problem statement, the chosen fix, test results, and screenshots or recordings for UI work. Link related issues and note any config or migration steps explicitly.
