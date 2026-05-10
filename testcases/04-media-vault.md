# 04 — Full docker-compose stack, S3 storage, Django-Tasks (RQ)

Covers full Compose dev mode, S3-compatible object storage, and the Django Tasks API with the Redis Queue backend.

## Prompt

```
/seedkit

Project name: 04-media-vault
Purpose: media-heavy app where uploads land in S3 and processing runs as Redis-queued background tasks.

Settings layout: split.
Database: PostgreSQL.
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
Add-ons:
  - redis
  - storage: S3-compatible (use MinIO in local Compose; configure via env)
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`)
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - CORS: yes.
  - REST API: `django-modern-rest` with the `msgspec` + `openapi` extras (`uv add 'django-modern-rest[msgspec,openapi]'`). Create an `api` app (`uv run manage.py startapp api`) with a single `MediaController` exposing `POST /api/media/` that accepts `{ "filename": str, "size": int }` (msgspec.Struct) and returns `{ "uid": uuid, "filename": str }`. Wire the `Router` from `api/urls.py` into `config/urls.py` under the `api` namespace. Do NOT add `dmr` to `INSTALLED_APPS`.
  - Frontend: none.
  - Devcontainer: yes.
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.

Production setup: skip.

Generate `docker-compose.yml` with services `web`, `db`, `redis`, `worker`, `minio`. Run the foundation, `docker compose up -d`, migrate, createsuperuser, and confirm a sample task enqueues and completes.
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
docker compose exec -T web uv run ruff check .
uv run pyright
# fail on any traceback / unhandled error in any service:
! docker compose logs web worker 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
# worker should print rqworker startup line:
docker compose logs worker 2>&1 | grep -iE 'rqworker|listening on|default'
docker compose down -v
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production}.py`, `Dockerfile.dev`, `docker-compose.yml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`.
- `docker-compose.yml` defines services `web`, `db`, `redis`, `worker`, `minio`. Named volumes for `pgdata`, `venv` (or `web-venv`), and `minio-data`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tasks`, `django-tasks-rq`, `django-storages[s3]` (or `boto3`), `django-cors-headers`, `django-modern-rest[msgspec,openapi]`, `pyjwt`, `structlog`. Dev deps include `ruff`, `pyright`, `django-stubs`, `django-stubs-ext`.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `config/settings/base.py` inside an `except ImportError: pass` guard.
- `STORAGES["default"]` resolves to `S3Boto3Storage` when `AWS_STORAGE_BUCKET_NAME` is set; falls back to `FileSystemStorage` when empty.
- `LOGGING` is at module scope (not inside `if DEBUG:`), with `json` and `console` formatters, `console` chosen when `DEBUG`.

**REST API**
- `INSTALLED_APPS` does NOT contain `dmr`.
- `api/` app with `controllers.py`, `schemas.py`, `urls.py`. `MediaController` typed with `Body[MediaCreate]` and a return type. Router mounted at `/api/` in `config/urls.py`.

**Logging**
- `config/middleware/logging.py` defines `RequestContextMiddleware` that binds `request_id` via `structlog.contextvars` and emits one log line per request. The middleware is in `MIDDLEWARE` after `AuthenticationMiddleware`.

**Tasks**
- `INSTALLED_APPS` includes `django_rq` and `django_tasks_rq`. `RQ_QUEUES` defined; `RQ = {"JOB_CLASS": "django_tasks_rq.Job"}` at module scope (not inside `RQ_QUEUES`).
- A registered Django app has `apps.py` with `ready()` importing `tasks`, and a `tasks.py` defining at least one `@task`.

**CORS + Devcontainer + Health**
- `corsheaders` in `INSTALLED_APPS`; `corsheaders.middleware.CorsMiddleware` BEFORE `CommonMiddleware`.
- `.devcontainer/devcontainer.json` parseable JSON: `"dockerComposeFile": ["../docker-compose.yml"]`, `"service": "web"`, `"workspaceFolder": "/app"`, `"shutdownAction": "stopCompose"`, `forwardPorts` includes `8000`. No secrets / DB passwords inline.
- `pages` app exposes `liveness` and `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
