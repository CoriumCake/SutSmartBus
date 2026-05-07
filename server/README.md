# SUT Smart Bus Server

FastAPI backend for the SUT Smart Bus monorepo.

## Run Locally

From the repository root:

```bash
docker-compose up -d --build
docker-compose logs -f
```

Health check:

```bash
curl http://localhost:8000/health
```

## Structure

```text
server/
|-- app/         # FastAPI app, routers, data access
|-- core/        # shared config and auth helpers
|-- routes/      # route and PM zone JSON data
|-- scripts/     # setup and operational helpers
|-- telemetry/   # telemetry-side utilities
|-- Dockerfile
`-- requirements.txt
```

## Notes

- Copy `server/.env.example` if you want local environment overrides.
- The Docker stack expects MongoDB and Mosquitto from the root `docker-compose.yml`.
- This folder lives in the same repository as the Flutter app and ESP32 firmware.

## Cloudflare Tunnel

For production, you can expose the FastAPI API and MQTT WebSocket endpoint through Cloudflare Tunnel instead of opening router port forwards for `8000` and `9001`.

1. Copy `server/.env.cloudflare.example` to `server/.env.cloudflare`.
2. In Cloudflare Zero Trust, create a tunnel using the Docker option and paste the generated token into `server/.env.cloudflare`.
3. In the Cloudflare dashboard, point your public hostnames to:
   - `https://api.your-domain.com` -> `http://server:8000`
   - `https://mqtt.your-domain.com` -> `http://mosquitto:9001`
4. Start the stack with the tunnel override:

```bash
docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d --build
```

This override keeps:

- `8000` bound to `127.0.0.1` on the host
- `9001` bound to `127.0.0.1` on the host
- `1883` still published directly for raw MQTT device traffic

Important: standard Cloudflare Tunnel does not replace raw MQTT/TCP on port `1883`. ESP32 devices using direct MQTT still need a direct reachable broker, or you will need a separate MQTT-over-WebSocket/TLS migration plan.
