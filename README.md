# 🚌 SUT Smart Bus

A smart campus bus tracking system for Suranaree University of Technology — combining IoT hardware, a real-time backend, and a Flutter mobile app.

## Repository Structure

```
SutSmartBus/
├── apps/
│   └── flutter/         # Flutter mobile app
├── server/              # FastAPI backend + Docker services
├── hardware/            # ESP32 / Arduino firmware
├── docker-compose.yml   # Root-level service orchestration
└── README.md
```

## Quick Start

### Server (Docker)

```bash
docker-compose up -d
```

This starts **MongoDB**, **Mosquitto MQTT**, and the **FastAPI server**.

### Production Tunnel

To stop exposing the API through router port forwarding, start the stack with the Cloudflare Tunnel override:

```bash
docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d --build
```

Setup steps live in [server/README.md](server/README.md). This production overlay moves `8000` and `9001` to localhost-only bindings and runs `cloudflared` in Docker.

### Flutter App

```bash
cd apps/flutter
flutter pub get
flutter run
```

### Hardware

See [`hardware/README.md`](hardware/README.md) for flashing instructions for each ESP32 module.

## Tech Stack

| Layer | Tech |
|-------|------|
| **Mobile** | Flutter, Riverpod, GoRouter, MQTT |
| **Server** | FastAPI, Motor (MongoDB), Paho MQTT |
| **Infra** | Docker, MongoDB 7, Eclipse Mosquitto |
| **Hardware** | ESP32-CAM, PM sensors, Arduino framework |
