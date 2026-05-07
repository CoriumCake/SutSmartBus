# GitHub Deployment Setup

This repository can deploy the backend automatically from GitHub Actions after pushes to `master`.

## What the workflow does

The workflow in `.github/workflows/deploy-production.yml`:

1. runs on a self-hosted GitHub Actions runner on the server
2. updates the repo checkout
3. writes the root `.env` file from GitHub secrets and variables
4. runs `docker compose up -d --build`
5. verifies `http://localhost:8000/health`

## Prerequisites on the server

- Docker and Docker Compose available on the server
- a clone of this repository already present on the server
- a self-hosted GitHub Actions runner installed on the server
- the runner user can execute the deployment commands in the repo directory
- the server can reach GitHub to pull changes

## Recommended GitHub production environment

Create a GitHub Actions environment named `production`.

### Environment secrets

- `DEPLOY_PATH`
- `API_SECRET_KEY`
- `ADMIN_PASSWORD`

### Environment variables

- `DEPLOY_BRANCH` = `master`
- `MQTT_BROKER_HOST` = `mosquitto`
- `MQTT_BROKER_PORT` = `1883`
- `MONGODB_URL` = `mongodb://mongodb:27017/sut_smart_bus`
- `TZ` = `Asia/Bangkok`
- `CORS_ORIGINS` = `*`
- `RATE_LIMIT_PER_MINUTE` = `60`
- `MAX_UPLOAD_SIZE` = `2097152`
- `OTA_FALLBACK_IP` = `203.158.3.14`
- `DB_FILE` = `bus_passengers.db`

## Self-hosted runner setup

Install a Linux self-hosted runner from:

- `Settings` -> `Actions` -> `Runners` -> `New self-hosted runner`

Run the GitHub-provided commands as a non-root user on the server, then install the runner as a service.

## First-time server prep

Example:

```bash
git clone https://github.com/CoriumCake/SutSmartBus.git /opt/SutSmartBus
cd /opt/SutSmartBus
git checkout master
docker compose up -d --build
```

Then set `DEPLOY_PATH` to that absolute path, for example `/opt/SutSmartBus`.
