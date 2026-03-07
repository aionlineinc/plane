# Deploying this Plane stack (Dokploy / Docker Compose)

This compose uses the **official Plane images** (`makeplane/plane-frontend:stable`, `makeplane/plane-backend:stable`) and is a minimal stack: web + api + worker + beat + db + redis + RabbitMQ + MinIO.

## Required environment variables

Set these in Dokploy **Environment** (or in a `.env` file next to the compose):

| Variable | Description |
|----------|-------------|
| `PLANE_DOMAIN` | Public host only, e.g. `pm.aient.co` (used in WEB_URL, CORS, and frontend API URL). |
| `DB_PASSWORD` | PostgreSQL password for user `plane`. |
| `SECRET_KEY` | Django secret key (long random string). |
| `MINIO_ROOT_USER` | MinIO admin user. |
| `MINIO_ROOT_PASSWORD` | MinIO admin password. |
| `RABBITMQ_PASSWORD` | RabbitMQ password for user `plane`. (Spelling: **RABBITMQ**, not RABBITMO.) |

Optional:

| Variable | Description |
|----------|-------------|
| `GUNICORN_WORKERS` | API worker processes (default `2`). If you set it in env, use a number (e.g. `1` or `2`); an empty value will crash the API. |

Optional (have defaults in compose):

- `RABBITMQ_USER` (default `plane`)
- `RABBITMQ_VHOST` (default `plane`)
- `AWS_S3_BUCKET_NAME` (default `uploads`)

## Routing (reverse proxy)

The compose does **not** include Plane’s proxy. You need a reverse proxy (e.g. Traefik via Dokploy) in front:

- **Option A – Single domain**  
  Point your domain at **one** service (e.g. `plane-web` on port 3000). Then either:
  - Route `/api` (and any other backend paths) to `plane-api:8000`, and set `NEXT_PUBLIC_API_BASE_URL=https://${PLANE_DOMAIN}` (so the frontend calls the same host; your proxy must forward `/api` to the backend), or
  - Use Plane’s **proxy** image in front of web + api (see [Plane self-hosting](https://developers.plane.so/self-hosting/overview)) and point your domain at the proxy.

- **Option B – Separate host/port for API**  
  Expose `plane-api` and set `NEXT_PUBLIC_API_BASE_URL` to that URL (e.g. `https://api.yourdomain.com`). Ensure CORS allows your web origin.

In Dokploy **Domains**, attach your host to the service that will receive traffic (e.g. `plane-web` container port **3000** if you only route to the frontend and your proxy handles `/api` elsewhere).

## First run: migrations

On first deploy, run migrations once. Either run a one-off migrator container with the same env as `plane-api`, or exec into the api container:

```bash
docker compose run --rm plane-api ./bin/docker-entrypoint-migrator.sh
# or
docker exec -it <plane-api-container> ./bin/docker-entrypoint-migrator.sh
```

(If your compose doesn’t define a migrator service, use the api container and the same env.)

## Data

All persistent data is in **named volumes** (`plane-db-data`, `plane-redis-data`, `plane-mq-data`, `plane-minio-data`, `plane-logs*`). Back them up if needed.

## Changes made in this compose

- **RabbitMQ** added: backend and Celery require it (worker/beat).
- **REDIS_URL** set to `redis://plane-redis:6379/0`.
- **Named volumes** instead of host paths so it works in Dokploy.
- **Entrypoint scripts** for api/worker/beat: `docker-entrypoint-api.sh`, `docker-entrypoint-worker.sh`, `docker-entrypoint-beat.sh`.
- **S3 bucket** default: `uploads` (override with `AWS_S3_BUCKET_NAME` if needed).
