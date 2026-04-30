# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SUT Smart Bus** is a real-time campus bus tracking system for Suranaree University of Technology. It combines ESP32 IoT hardware, a FastAPI backend, and a Flutter mobile app.

## Commands

### Full Stack (Docker)
```bash
docker-compose up -d --build     # Start all services (MongoDB, Mosquitto MQTT, FastAPI)
docker-compose logs -f           # Tail logs
docker-compose down              # Stop services
docker-compose down -v           # Stop and delete volumes (destroys data)
```

### Flutter App
```bash
cd apps/flutter
flutter pub get
flutter run
flutter build apk
flutter test
```

### Server Utilities
```bash
cd server
python register_bus.py --mac "XX:XX:XX:XX:XX:XX" --name "BUS-01"
python seed_pm_zones.py
python scripts/ota_trigger.py
```

## Architecture

### Data Flow
```
ESP32 Hardware → MQTT (Mosquitto :1883) → FastAPI (Motor/async) → MongoDB
                                                     ↓
                                    Mobile App (REST + MQTT WebSocket)
```

### Service Ports
| Service | Port | Notes |
|---------|------|-------|
| FastAPI | 8000 | Main API |
| MongoDB | 27017 | |
| MQTT | 1883 | Devices |
| MQTT WS | 9001 | Mobile app WebSocket |

### Backend (`server/`)
- **`app/main.py`** — FastAPI app entry, middleware registration, MQTT + DB lifespan setup
- **`app/mqtt.py`** — MQTT subscription handler; updates bus state in MongoDB, runs geo-polygon checks against PM zones
- **`app/routers/`** — 10 route modules: buses, routes, ota, passengers, pm_zones, dashboard, admin, analytics, feedback, system
- **`core/config.py`** — Pydantic Settings (reads `.env`)
- **`core/auth.py`** — Optional `X-API-Key` header middleware (disabled when `API_SECRET_KEY` is unset)

### MQTT Topics
| Topic | Direction | Publisher | Payload |
|-------|-----------|-----------|---------|
| `sut/bus/gps` | → Server | PM Module | `{lat, lon, pm2_5, pm10, temp, hum, bus_mac}` |
| `sut/bus/gps/fast` | → Server | PM Module | GPS-only, 500ms |
| `bus/door/count` | → Server | ESP32-CAM | `{dir:"enter"/"exit", count:N}` |
| `sut/bus/ring` | ← Server | | Ring bell command |
| `sut/ota/pm` | ← Server | | OTA firmware URL |
| `sut/ota/esp32_cam` | ← Server | | OTA firmware URL |

### Mobile App (`apps/flutter/`)
- **Navigation:** GoRouter with a splash route, consent gate, shell tabs, and stacked admin/detail screens
- **State:** Riverpod providers and notifiers
- **Real-time:** MQTT client + Dio for REST
- **Connection modes:** Configured in `lib/config/`

### Hardware (`hardware/`)
- **`pm/`** — Main tracker: ESP32 + NEO-6M GPS + PMS5003 (PM2.5/PM10) + DHT11 + DS3231 RTC; publishes every 30s
- **`esp32_cam/`** — Door camera: AI-Thinker ESP32-CAM; detects enter/exit and publishes person counts
- All modules require copying `config.h.example` → `config.h` and filling in WiFi/MQTT credentials before flashing

### Migration Notes (`migrate/`)
The `migrate/` directory is historical reference material from the React Native to Flutter migration. New work should target `apps/flutter/`.

## Environment Configuration

**`server/.env`** (not committed; copy from `server/.env.example`):
```
MQTT_BROKER_HOST=mosquitto
MQTT_BROKER_PORT=1883
MONGODB_URL=mongodb://mongodb:27017/sut_smart_bus
TZ=Asia/Bangkok
API_SECRET_KEY=           # Leave empty to disable auth
CORS_ORIGINS=*
```

**Mobile:** Edit the files in `apps/flutter/lib/config/` to switch between local and tunnel mode.

**Hardware:** Each module's `config.h` holds WiFi SSID/password and MQTT broker IP.
