# Deploying this Plane stack (Dokploy / Docker Compose)

This compose uses the **official Plane images** (`makeplane/plane-frontend:stable`, `makeplane/plane-backend:stable`) and is a minimal stack: web + api + worker + beat + db + redis + RabbitMQ + MinIO.

---

## Why this is fiddly on Dokploy (and easier options)

Plane is a **multi-service** app (frontend, API, workers, DB, Redis, RabbitMQ, MinIO) that expects **one public URL** with `/api` and `/auth` going to the backend. Dokploy’s “one domain → one service” and internal networking don’t match that out of the box, so we added a custom proxy, env defaults, and healthchecks. That’s why you hit routing, 502, CSRF, and unhealthy dependency issues.

**Easier options:**

1. **Plane Cloud** – [app.plane.so](https://app.plane.so): hosted by Plane, no Docker or Dokploy. Easiest if you’re okay with their hosting.

2. **Official Plane compose on a VPS (no Dokploy)** – On a server with Docker installed, clone [makeplane/plane](https://github.com/makeplane/plane), use their **official** `docker-compose.yml` (or the one under `deployments/`). Run `docker compose up -d`, point your domain at the **proxy** service (port 80). No Domains tab, no custom proxy—their setup is designed for that. Use Caddy or Traefik in front only if you need TLS or multiple apps.

3. **Use Plane’s full stack in Dokploy** – If you deploy Plane’s **full** compose (including their **plane-proxy** image) and in Dokploy attach your domain **only** to that proxy service (port 80), you may avoid our custom nginx and path-routing. You’d still set env vars and run migrations per Plane’s docs.

4. **Keep this repo** – If you’ve got it working (or nearly), the rest of this doc is for this minimal stack and troubleshooting.

---

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

### Domains tab (Dokploy) – use the proxy

A **plane-proxy** (Nginx) service is the single entry point: it forwards **`/api`** and **`/auth`** to the backend and everything else to the frontend. This avoids 405s regardless of how Dokploy/Traefik handles labels.

**Set the Domains tab like this:**

1. Add your domain (e.g. **`pm.aient.co`**).
2. Attach it to the **plane-proxy** service (not plane-web or plane-api).
3. Set **container port** to **80**.
4. Enable **HTTPS** / Let’s Encrypt if your setup offers it.

All traffic for your domain goes to plane-proxy; Nginx then routes `/api` and `/auth` to the API and the rest to the web app. No need to rely on Traefik path-based routing or leave the Domains tab empty.

---

### How to attach the domain only to plane-proxy (step-by-step)

Dokploy’s UI varies by version; the idea is always: **domain → one service + port**.

1. **Open the app**
   - In Dokploy, open the project that runs this Plane stack.
   - Open the app that uses `docker-compose.dokploy.yml` (e.g. “Plane” or “barbadosorg-plane-firple”).

2. **Open Domains**
   - Find the **Domains** (or **Domain**, **Routing**, **Ingress**) tab/section for this app and open it.

3. **Remove the domain from other services (if it’s there)**
   - If **pm.aient.co** is already listed and tied to **plane-web** or **plane-api** (or any service other than plane-proxy), **remove** that domain entry or change it so the domain is no longer attached to that service.
   - Some UIs show “Domain X → Service Y, port Z”. Ensure no row says pm.aient.co → plane-web or plane-api.

4. **Add / assign the domain to plane-proxy**
   - **Add domain** (or **Add Domain** / **Configure domain**):
     - **Domain / host:** `pm.aient.co` (no `https://` or path).
     - **Service / container:** choose **plane-proxy** (the nginx service in this compose). The list may show the service name from the compose, e.g. **plane-proxy** or a generated name containing “proxy”.
     - **Port / container port:** **80**.
   - If the UI has a **single** “Domain” field and a **separate** “Service” dropdown, set Domain = `pm.aient.co`, Service = **plane-proxy**, Port = **80**.
   - Save (e.g. **Save**, **Update**, **Deploy**).

5. **Redeploy if needed**
   - If Dokploy asks to redeploy or “Apply” after changing domains, do it so the reverse proxy (e.g. Traefik) picks up the new route.

6. **Check the result**
   - After a minute, open `https://pm.aient.co`. The site should load.
   - Try the login flow; in DevTools → Network, the **POST** to `/auth/email-check/` should return **200** and have **X-Served-By: plane-proxy-api** in response headers.

**If you don’t see “plane-proxy” in the service list:**  
The names might be prefixed (e.g. `barbadosorg-plane-firple-plane-proxy-1`). Pick the one that corresponds to the **proxy** container (the nginx one that runs `proxy/nginx.conf`), not web or api.

Config for the proxy is in **`proxy/nginx.conf`** (mounted into the plane-proxy container).

**Still getting 405 on POST /auth/email-check/?**

That usually means the request is **not** going through plane-proxy to the API; it’s hitting the **frontend** (plane-web), which doesn’t handle that route and returns 405.

1. **Check who answered**  
   In the browser: **DevTools → Network** → click the failed **POST** request to `/auth/email-check/` → **Headers** tab → **Response Headers**:
   - **`X-Served-By: plane-proxy-api`** → request reached the API. If you still see 405, the API is returning it (rare for this endpoint).
   - **`X-Served-By: plane-proxy-web`** or **no X-Served-By** → request hit the frontend. So the domain is **not** going to plane-proxy. Fix step 2.

2. **Point the domain only at plane-proxy**  
   In Dokploy → your Plane app → **Domains**:
   - **Remove** the domain from any other service (e.g. plane-web). If the domain is attached to plane-web, all traffic (including `/auth/`) goes to the frontend and you get 405.
   - **Add** the domain (e.g. `pm.aient.co`) and attach it **only** to **plane-proxy**, container port **80**. Save and redeploy if needed.
   - Some UIs let you pick “which service” gets the domain; choose **plane-proxy**. If the domain can only be attached to one service, that one must be plane-proxy.

3. **Verify from the command line**  
   From your machine run:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" -X POST https://pm.aient.co/auth/email-check/
   ```
   Then:
   ```bash
   curl -I -X POST https://pm.aient.co/auth/email-check/
   ```
   Check the response headers for **X-Served-By**. If you see **X-Served-By: plane-proxy-api** and 200/400 (not 405), the proxy and API are correct.

4. **React error #418** in the console is a **hydration** issue, not the 405. Fix routing first.

---

### 502 Bad Gateway

The proxy (or Traefik) is reaching your app but the upstream (plane-proxy, or plane-api/plane-web behind it) is not responding. Common causes:

**1. plane-api is down or crashing**  
Most likely after switching to **building the API from source**: the build may have failed, or the API container may be exiting (e.g. missing deps, import error).

- In Dokploy, open **Logs** for **plane-api**. If you see Python tracebacks, build errors, or the container restarting, the custom image is failing.
- **Quick rollback:** In `docker-compose.dokploy.yml`, change **plane-api** back to the pre-built image and drop the build:
  - Remove the `build:` block and set `image: makeplane/plane-backend:stable` again.
  - Set **plane-worker**, **plane-beat**, and **plane-migrator** back to `image: makeplane/plane-backend:stable`.
  - Redeploy. You’ll get the site back but may see **403** on login again (CSRF) until you fix the build or use a different approach.

**2. plane-web is down**  
Check **plane-web** logs. If it’s crashing, the frontend won’t load and the proxy returns 502 for `/`.

**3. plane-proxy is down or wrong port**  
Confirm the domain in the Domains tab points to **plane-proxy**, port **80**. If it points to another service or wrong port, you can get 502.

**4. plane-api "unhealthy" or "dependency failed to start"**
The API healthcheck was updated to use **Python** (no curl) and a **start_period: 90s** so the API has time to start before being marked unhealthy. If the API still fails healthchecks, check **plane-api** logs (entrypoint errors, DB connection, GUNICORN_WORKERS, etc.).

**5. Containers still starting**  
After deploy, wait 1–2 minutes for plane-api (and plane-web) to finish migrations and listen on 8000/3000. Retry the page. The compose now makes **plane-proxy** wait for **plane-api** to be **healthy** before starting, which reduces 502s while the API is still starting.

**6. 502 only on POST /auth/email-check/ and no API log activity**  
If **plane-api** logs show no request when you try to log in, the request **never reaches the API**. So either:

- **Domain points at the wrong service**  
  In Dokploy **Domains**, the host (e.g. `pm.aient.co`) must be attached to **plane-proxy**, port **80**, not to plane-web or plane-api. If it’s attached to **plane-web**, all traffic (including POST /auth/email-check/) goes to the frontend; the API gets nothing and you see 502 and no API logs.

- **Proxy can’t reach the API**  
  From the server, test from inside the proxy container (replace `<proxy-container>` with the real name, e.g. from `docker ps`):
  ```bash
  docker exec <proxy-container> wget -q -O - http://plane-api:8000/
  ```
  If this fails, plane-proxy and plane-api are not on the same network or the API isn’t listening. Ensure both use the same compose file and the same networks (default + dokploy-network).

**Quick check:** In Domains, if the target is **plane-web** or shows port **3000**, change it to **plane-proxy** and port **80**, save, redeploy if needed, then try again.

**7. Domain is on proxy:80 but still 502 and no API logs (cannot run docker exec)**  
The proxy may be unable to reach the API because your platform uses a **different internal hostname** for the API (e.g. a long container name instead of `plane-api`). The proxy now supports **configurable upstream hostnames**:

- In the **plane-proxy** service, set environment variables (in Dokploy **Environment** or in the compose):
  - **`UPSTREAM_API`** = internal hostname of the API container (default: `plane-api`). If Dokploy shows something like `barbadosorg-plane-firple-plane-api-1` as the API service hostname, set `UPSTREAM_API=barbadosorg-plane-firple-plane-api-1` (or whatever your UI shows).
  - **`UPSTREAM_WEB`** = internal hostname of the web container (default: `plane-web`). Override only if needed.

- **Finding the hostname in Dokploy:** In the app’s service list or details, check the API service for “Internal hostname”, “Service name”, “Container name”, or the hostname other services use to reach it. Use that value for `UPSTREAM_API`. If everything is deployed from the same compose and Dokploy uses standard Compose networking, `plane-api` and `plane-web` should work; try the overrides only if 502 persists.

---

### 400 "Instance not configured. Please contact your administrator."

The API is reachable (routing is correct) but the **instance** is not marked as “setup done”, so auth endpoints return 400.

**Fix:** From inside the **API container** (Dokploy → open terminal for **plane-api** → `cd /code`), run:

```bash
python manage.py shell -c "
from plane.license.models import Instance
i = Instance.objects.first()
if i:
    i.is_setup_done = True
    i.save()
    print('Instance marked as setup done.')
else:
    print('No Instance found.')
"
```

Then try logging in again. You must have created the first admin (createsuperuser + create_instance_admin) before or after this.

---

### 403 Forbidden on POST /auth/email-check/

The API is reached (routing is correct) but Django’s **CSRF** check fails: the login form POSTs without sending the CSRF token, so Django returns 403.

**1. Check CORS / CSRF trusted origin**

In the **plane-api** service, ensure the env has:

- `CORS_ALLOWED_ORIGINS=https://pm.aient.co` (no trailing slash; same as your real URL).

That sets `CSRF_TRUSTED_ORIGINS` so Django trusts your origin. If it was wrong or missing, fix it, redeploy, and try again.

**2. CSRF exempt for email-check (already applied in this repo)**

The pre-built frontend does not send the CSRF token for the email-check request. This repo already applies the fix:

- **Code:** In `apps/api/plane/authentication/urls.py`, the `email-check/` and `spaces/email-check/` views are wrapped with `csrf_exempt`.
- **Compose:** The API is **built from source** (`apps/api`, `Dockerfile.api`) and tagged as `plane-backend:local`; worker, beat, and migrator use the same image. So when you deploy from this repo, the patched backend is used and login should work without 403 on email-check.

If you switch back to `image: makeplane/plane-backend:stable` (no build), you would get 403 again unless you use a backend image that includes this patch.

### Using another proxy (Nginx, Caddy, etc.)

Route by path:

- **`/api`** and **`/auth`** → proxy to **plane-api:8000**
- **`/`** (default) → proxy to **plane-web:3000**

Then point your domain at that proxy.

## Create first admin (when you never get to create login)

If you only see the **login** screen and never see **"Let's secure your instance"** (so you can't create the first account), create the first user from the server.

You can do this in either of two ways:

---

### From inside the API container (Dokploy “Terminal” / “Exec”)

If you open a terminal in Dokploy and it drops you into a container (you see a prompt like `23c32efe898e:/#`), **you’re already inside the API container**. Docker isn’t available there; run the Django commands directly (no `docker exec`). The app lives in `/code`, so run:

```bash
cd /code
```

**1. Create the first user**

```bash
python manage.py createsuperuser
```

Enter **email**, **username** (e.g. `admin`), and **password** when prompted.

**2. Make that user Instance Admin**

```bash
python manage.py create_instance_admin YOUR_EMAIL@example.com
```

Use the **exact** email from step 1.

**3. Enable password login**

```bash
python manage.py shell -c "
from plane.app.db.models import InstanceConfiguration
InstanceConfiguration.objects.filter(key='ENABLE_EMAIL_PASSWORD').update(value='1')
InstanceConfiguration.objects.filter(key='ENABLE_SIGNUP').update(value='1')
print('Done.')
"
```

If that fails (e.g. wrong model path), try:

```bash
python manage.py shell -c "
from django.apps import apps
m = apps.get_model('db', 'InstanceConfiguration')
m.objects.filter(key='ENABLE_EMAIL_PASSWORD').update(value='1')
m.objects.filter(key='ENABLE_SIGNUP').update(value='1')
print('Done.')
"
```

**4. Mark the instance as configured** (so login no longer returns “Instance not configured”):

```bash
python manage.py shell -c "
from plane.license.models import Instance
i = Instance.objects.first()
if i:
    i.is_setup_done = True
    i.save()
    print('Instance marked as setup done.')
else:
    print('No Instance found - create one or run migrations.')
"
```

**5. Log in** at `https://your-domain` with that email and password, then open **/god-mode** if needed.

---

### From the server (SSH or host shell)

If you have SSH (or a “host” shell) on the machine where Docker runs, use the container name and `docker exec`:

**1. Find the API container**

```bash
docker ps --format "{{.Names}}" | grep -i api
```

Use that name as `<API_CONTAINER>` below (e.g. `barbadosorg-plane-firple-plane-api-1`).

**2. Create the first user**

```bash
docker exec -it <API_CONTAINER> python manage.py createsuperuser
```

**3. Make that user Instance Admin**

```bash
docker exec -it <API_CONTAINER> python manage.py create_instance_admin YOUR_EMAIL@example.com
```

**4. Enable password login**

```bash
docker exec -it <API_CONTAINER> python manage.py shell -c "
from plane.app.db.models import InstanceConfiguration
InstanceConfiguration.objects.filter(key='ENABLE_EMAIL_PASSWORD').update(value='1')
InstanceConfiguration.objects.filter(key='ENABLE_SIGNUP').update(value='1')
print('Done.')
"
```

(If the import fails, use the `django.apps` version from the “From inside the API container” section above, inside the same `docker exec ... shell -c "..."`.)

**5. Log in in the browser**

Open your instance (e.g. `https://pm.aient.co`), log in with the **email** and **password** from step 2. Then open **/god-mode** to configure auth and SMTP if needed.

---

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

(All in **`docker-compose.dokploy.yml`** and **`proxy/nginx.conf`**.)

- **plane-proxy** (Nginx): single entry point so the Domains tab can point to one service; routes `/api` and `/auth` to the API, everything else to the web app (fixes 405 when Dokploy/Traefik don’t do path-based routing).
- **CSRF exempt** for `/auth/email-check/` and `/auth/spaces/email-check/` is applied in **code** (`apps/api/plane/authentication/urls.py`) for when you **build the API from source**. The compose currently uses the **pre-built** image `makeplane/plane-backend:stable` to avoid 502 (build-from-source can fail in some environments). To get login without 403, you’d need to build the API from this repo and use that image for api/worker/beat/migrator.
- **RabbitMQ** added: backend and Celery require it (worker/beat).
- **REDIS_URL** set to `redis://plane-redis:6379/0`.
- **Named volumes** instead of host paths so it works in Dokploy.
- **Entrypoint scripts** for api/worker/beat: `docker-entrypoint-api.sh`, `docker-entrypoint-worker.sh`, `docker-entrypoint-beat.sh`.
- **S3 bucket** default: `uploads` (override with `AWS_S3_BUCKET_NAME` if needed).
