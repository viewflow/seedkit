# 04 — Full docker-compose stack, ASGI + channels, S3 storage, Django-Tasks (RQ)

Covers full Compose dev mode, ASGI + django-channels (WebSockets with channels-redis layer), S3-compatible object storage, and the Django Tasks API with the Redis Queue backend.

## Prompt

```
/seedkit

Project name: 04-media-vault
Purpose: media-heavy app where uploads land in S3, processing runs as Redis-queued background tasks, and clients subscribe over WebSockets for status updates.

Settings layout: split.
Database: PostgreSQL.
Request handling: asgi+channels.
Local dev mode: docker-compose (full stack: web + db + redis).
Docker structure: simple (separate `Dockerfile.dev`, single `docker-compose.yml`).
Lint with Ruff: yes.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Task runner: none.
Add-ons:
  - redis
  - storage: S3-compatible (use MinIO in local Compose; configure via env)
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`). Also `uv run manage.py startapp jobs`, register `jobs` in `INSTALLED_APPS`, wire `jobs/apps.py` `ready()` to import `tasks`, and add a sample `@task` to `jobs/tasks.py`.
  - real-time channel layer: `channels-redis` (reuse the same Redis service). Add an `EchoConsumer` (`AsyncJsonWebsocketConsumer`) that echoes received JSON back to the sender, routed at `/ws/echo/` in `config/routing.py`. Wire `config/asgi.py` with `ProtocolTypeRouter` + `AllowedHostsOriginValidator` + `AuthMiddlewareStack` per `references/realtime.md`.
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - CORS: yes.
  - REST API: `django-modern-rest` with the `msgspec` + `openapi` extras (`uv add 'django-modern-rest[msgspec,openapi]'`). Create an `api` app (`uv run manage.py startapp api`) with a single `MediaController` exposing `POST /api/media/` that accepts `{ "filename": str, "size": int }` (msgspec.Struct) and returns `{ "uid": uuid, "filename": str }`. Wire the `Router` from `api/urls.py` into `config/urls.py` under the `api` namespace. Do NOT add `dmr` to `INSTALLED_APPS`.
  - Frontend: none.
  - Devcontainer: yes.
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.

Production setup: skip.

Generate `docker-compose.yml` with services `web`, `db`, `redis`, `worker`, `minio`. `web` runs `gunicorn -k uvicorn.workers.UvicornWorker config.asgi:application` (uvicorn worker since the foundation picked ASGI; HTTP and WS share the same process in dev). Run the foundation, `docker compose up -d`, migrate, createsuperuser, and confirm both a sample task enqueues and a WebSocket round-trip works.
```

## Boot check

```sh
cd 04-media-vault
docker compose up -d
docker compose ps
docker compose exec -T web uv run manage.py migrate
docker compose exec -T web uv run manage.py createsuperuser --noinput || true
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf -X POST http://127.0.0.1:8000/api/media/ \
  -H 'content-type: application/json' \
  -d '{"filename":"a.png","size":42}' > /dev/null
! curl -sf -X POST http://127.0.0.1:8000/api/media/ \
  -H 'content-type: application/json' \
  -d '{"filename":"a.png"}' > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# WebSocket round-trip — uses the `websockets` lib (already a transitive
# dep of uvicorn[standard]). Connects, sends one message, expects it
# back. Times out at 5s.
uv run python -c "
import asyncio, json, websockets

async def main():
    # AllowedHostsOriginValidator requires an Origin header; the Python
    # websockets client doesn't send one by default.
    async with websockets.connect('ws://127.0.0.1:8000/ws/echo/', origin='http://localhost') as ws:
        await ws.send(json.dumps({'text': 'ping'}))
        reply = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert reply == {'text': 'ping'}, reply

asyncio.run(main())
"
docker compose exec -T web uv run ruff check .
uv run pyright
# fail on any traceback / unhandled error in any service:
! docker compose logs web worker 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
# worker should print rqworker startup line:
docker compose logs worker 2>&1 | grep -iE 'rqworker|listening on|default'
# uvicorn worker should announce itself in web logs:
docker compose logs web 2>&1 | grep -iE 'uvicorn|uvicornworker|asgi'
docker compose down -v
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production}.py`, `config/asgi.py`, `config/routing.py`, `Dockerfile.dev`, `docker-compose.yml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`.
- `docker-compose.yml` defines services `web`, `db`, `redis`, `worker`, `minio`. Named volumes for `pgdata`, `venv` (or `web-venv`), and `minio-data`. `web` service `command:` (or `Dockerfile.dev` `CMD`) invokes `gunicorn -k uvicorn.workers.UvicornWorker config.asgi:application --bind 0.0.0.0:8000` (or `uvicorn config.asgi:application --reload --host 0.0.0.0` in dev — either is acceptable as long as it's an ASGI server, not `manage.py runserver`).
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tasks`, `django-tasks-rq`, `django-storages[s3]` (or `boto3`), `django-cors-headers`, `django-modern-rest[msgspec,openapi]`, `channels`, `channels-redis`, `daphne`, `uvicorn`, `gunicorn`, `pyjwt`, `structlog`, `django-structlog`. Dev deps include `ruff`, `pyright`, `django-stubs`, `django-stubs-ext`.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `config/settings/base.py` inside an `except ImportError: pass` guard.
- `STORAGES["default"]` resolves to `S3Boto3Storage` when `AWS_STORAGE_BUCKET_NAME` is set; falls back to `FileSystemStorage` when empty.
- `LOGGING` is at module scope (not inside `if DEBUG:`), with `json` and `console` formatters, `console` chosen when `DEBUG`.
- `INSTALLED_APPS` includes `daphne` and `channels`. `ASGI_APPLICATION = "config.asgi.application"`. `CHANNEL_LAYERS["default"]["BACKEND"]` = `"channels_redis.core.RedisChannelLayer"` with `CONFIG` reading `hosts` from `REDIS_URL`.
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`. `config/asgi.py` defaults to `config.settings.production`. `config/wsgi.py` remains at the `startproject` default (unchanged) — the deploy loads `asgi.py`, not `wsgi.py`.

**ASGI + channels**
- `config/asgi.py` constructs `ProtocolTypeRouter({"http": django_asgi_app, "websocket": AllowedHostsOriginValidator(AuthMiddlewareStack(URLRouter(websocket_urlpatterns)))})` per `references/realtime.md`. `django.setup()` is called before importing `config.routing`.
- `config/routing.py` defines `websocket_urlpatterns` containing one `path("ws/echo/", EchoConsumer.as_asgi())` entry.
- A consumer module (e.g. `jobs/consumers.py` or `realtime/consumers.py`) defines `EchoConsumer(AsyncJsonWebsocketConsumer)` with at least `connect` (awaits `self.accept()`) and `receive_json` (echoes the same JSON back via `self.send_json`).

**REST API**
- `INSTALLED_APPS` does NOT contain `dmr`.
- `api/` app with `controllers.py`, `schemas.py`, `urls.py`. `MediaController` typed with `Body[MediaCreate]` and a return type. Router mounted at `/api/` in `config/urls.py`.

**Logging**
- `django_structlog.middlewares.RequestMiddleware` in `MIDDLEWARE` directly after `AuthenticationMiddleware`. `django_structlog` in `INSTALLED_APPS`. `pyproject.toml` runtime deps include `django-structlog`.

**Tasks**
- `INSTALLED_APPS` includes `django_rq` and `django_tasks_rq`. `RQ_QUEUES` defined; `RQ = {"JOB_CLASS": "django_tasks_rq.Job"}` at module scope (not inside `RQ_QUEUES`).
- A registered Django app has `apps.py` with `ready()` importing `tasks`, and a `tasks.py` defining at least one `@task`.

**CORS + Devcontainer + Health**
- `corsheaders` in `INSTALLED_APPS`; `corsheaders.middleware.CorsMiddleware` BEFORE `CommonMiddleware`.
- `.devcontainer/devcontainer.json` parseable JSON: `"dockerComposeFile": ["../docker-compose.yml"]`, `"service": "web"`, `"workspaceFolder": "/app"`, `"shutdownAction": "stopCompose"`, `forwardPorts` includes `8000`. No secrets / DB passwords inline.
- `pages` app exposes `liveness` and `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
