# SUT Smart Bus

SUT Smart Bus is a single repository for the mobile app, backend services, and ESP32 firmware used by the campus bus tracking system.

## Monorepo Layout

```text
SutSmartBus/
|-- apps/
|   `-- flutter/      # Flutter client
|-- server/           # FastAPI API, Docker config, scripts
|-- hardware/         # ESP32 and sensor firmware
|-- migrate/          # migration notes and architecture docs
|-- docker-compose.yml
`-- README.md
```

## Quick Start

### Backend

From the repository root:

```bash
docker-compose up -d --build
docker-compose logs -f
```

Health check:

```bash
curl http://localhost:8000/health
```

### Flutter App

From `apps/flutter/`:

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

If generated Dart code needs to be refreshed:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Hardware

Firmware lives in `hardware/`.

- `hardware/esp32_cam/`: passenger counting and camera unit
- `hardware/pm/`: GPS and air-quality unit
- `hardware/get_mac_address/`: helper sketch for device registration

See [hardware/README.md](/C:/Users/maple/Documents/Coding/SutSmartBus/hardware/README.md) for setup details.

## Repo Notes

- Generated Flutter build output and local secrets are intentionally ignored.
- Use [server/.env.example](/C:/Users/maple/Documents/Coding/SutSmartBus/server/.env.example) and [.env.example](/C:/Users/maple/Documents/Coding/SutSmartBus/.env.example) as templates for local configuration.
- The repo is already organized as a monorepo, so cleanup is mostly about keeping build artifacts and tool-specific files out of source control.
- GitHub Actions can read the same keys through repository `Secrets` and `Variables`, especially `API_SECRET_KEY` and `ADMIN_PASSWORD`.
- Production deployment can be automated with [migrate/14_github_deploy.md](/C:/Users/maple/Documents/Coding/SutSmartBus/migrate/14_github_deploy.md).
