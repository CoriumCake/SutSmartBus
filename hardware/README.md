# SUT Smart Bus Hardware

ESP32 firmware for the SUT Smart Bus monorepo.

## Components

### ESP32-CAM (`esp32_cam/`)

Passenger counting and camera module mounted at the bus door.

### PM Sensor (`pm/`)

GPS tracking and air-quality monitoring unit.

### MAC Address Utility (`get_mac_address/`)

Helper sketch used during device registration.

## Setup

### ESP32-CAM

1. Edit `config.h` with Wi-Fi and MQTT settings.
2. Upload with the `AI-Thinker ESP32-CAM` board profile.
3. For the app ring button, make sure `RING_COMMAND_SECRET` matches the
   backend `RING_COMMAND_SECRET` or `API_SECRET_KEY`, and set `BUS_MAC_ALIAS`
   to the same logical bus MAC used by the app/backend bus mapping.

### PM Sensor

1. Copy `config.h.example` to `config.h`.
2. Fill in Wi-Fi, MQTT, and bus identification settings.
3. Upload with the `ESP32 Dev Module` board profile.

## Related Modules

- [server](/C:/Users/maple/Documents/Coding/SutSmartBus/server/README.md) - FastAPI backend and Docker services
- [apps/flutter](/C:/Users/maple/Documents/Coding/SutSmartBus/apps/flutter/README.md) - Flutter mobile app
