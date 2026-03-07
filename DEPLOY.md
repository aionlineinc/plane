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

## Routing (reverse proxy) – important

The frontend calls the **same origin** (e.g. `https://pm.aient.co`) for API requests. So the backend must be reachable at the same host under paths like **`/api`** and **`/auth`**. If everything is sent to the web container, you get **405 Method Not Allowed** on `POST /auth/email-check/` and similar, because the web app only serves pages and does not implement those endpoints.

### Using Traefik (e.g. Dokploy)

This compose adds **Traefik labels** so that, when the stack is on the same network as Traefik (`dokploy-network`):

- **`https://${PLANE_DOMAIN}/api`** and **`https://${PLANE_DOMAIN}/auth`** → **plane-api:8000**
- **`https://${PLANE_DOMAIN}/`** (everything else) → **plane-web:3000**

Ensure:

1. **`PLANE_DOMAIN`** is set in the environment (e.g. `pm.aient.co`).
2. The **`dokploy-network`** exists and Traefik is attached to it. If your Traefik network has another name, change the `networks` section and the `plane-web` / `plane-api` `networks` in the compose to use that name. Create the network if needed: `docker network create dokploy-network`.
3. **Do not** attach the domain to a single service in Dokploy’s Domains tab if that would send all traffic to one container; the labels above define the correct routing. If Dokploy still attaches the domain to one service, remove that and rely on the labels, or configure path-based routing in your proxy to match the behaviour above.

If your Traefik uses another **entrypoint** (e.g. `web` instead of `websecure`) or no TLS, change the `entrypoints` / `tls` labels on `plane-web` and `plane-api` accordingly.

### Using another proxy (Nginx, Caddy, etc.)

Route by path:

- **`/api`** and **`/auth`** → proxy to **plane-api:8000**
- **`/`** (default) → proxy to **plane-web:3000**

Then point your domain at that proxy.

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
