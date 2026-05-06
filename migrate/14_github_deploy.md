# GitHub Deployment Setup

This repository can deploy the backend automatically from GitHub Actions after pushes to `master`.

## What the workflow does

The workflow in `.github/workflows/deploy-production.yml`:

1. connects to your server over SSH
2. updates the repo checkout
3. writes the root `.env` file from GitHub secrets and variables
4. runs `docker compose up -d --build`
5. verifies `http://localhost:8000/health`

## Prerequisites on the server

- Docker and Docker Compose available from the shell used by SSH
- a clone of this repository already present on the server
- the SSH user can run `docker compose` in the repo directory
- the server can reach GitHub to pull changes

## Recommended GitHub production environment

Create a GitHub Actions environment named `production`.

### Environment secrets

- `DEPLOY_HOST`
- `DEPLOY_PORT`
- `DEPLOY_USER`
- `DEPLOY_SSH_KEY`
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

## SSH key setup

Generate a dedicated deploy key pair and add the public key to the target server user:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy"
```

Save the private key content as the GitHub secret `DEPLOY_SSH_KEY`.

## First-time server prep

Example:

```bash
git clone https://github.com/CoriumCake/SutSmartBus.git /opt/SutSmartBus
cd /opt/SutSmartBus
git checkout master
docker compose up -d --build
```

Then set `DEPLOY_PATH` to that absolute path, for example `/opt/SutSmartBus`.
