# 07 — Production: VPS deploy, SQLite mini-prod, single-stage Dockerfile, Sentry

Covers the SQLite mini-prod path on a single VPS: WAL-tuned `production.py`, separate `cache.sqlite3` for the cache backend, `django-tasks-db` for background work (no broker), Litestream replication to S3, Caddy + single-stage Dockerfile, security settings, Sentry SaaS error reporting, GitHub Actions test CI.

## Prompt

```
/seedkit

Project name: 07-vps-sqlite-saas
Purpose: production-ready SaaS skeleton deployed to a single VPS via docker-compose + Caddy, using the SQLite mini-prod stack (no separate DB / cache / queue server).

Settings layout: split.
Database: SQLite.
Local dev mode: docker-compose (full stack: web only — no db / redis services).
Docker structure: simple (separate `Dockerfile.dev` for dev, single-stage production `Dockerfile`).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: yes.
Internationalisation (i18n): no.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login + mandatory verification).
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Task runner: mise.
Add-ons:
  - cache backend: sqlite (separate `cache.sqlite3` + `CacheRouter` + `DatabaseCache`)
  - tasks: Django Tasks with the Database backend (`django-tasks-db`). Also `uv run manage.py startapp jobs`, register `jobs` in `INSTALLED_APPS`, wire `jobs/apps.py` `ready()` to import `tasks`, and add a sample `@task` to `jobs/tasks.py`.
  - storage: WhiteNoise (static), media volume on the VPS host
  - email: SMTP in production, console backend in local. Use a placeholder Postmark URL (`EMAIL_URL=smtp+tls://<token>:<token>@smtp.postmarkapp.com:587`); also wire `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`, `DJANGO_ADMINS`.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: `django-axes` (yes), 2FA (yes).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings (HSTS, secure cookies, X-Frame, SSL redirect)
  - CSP via `django-csp`: yes
  - error reporting: Sentry SaaS (sentry-sdk)
  - CI: GitHub Actions test workflow
  - deploy target: VPS (Docker + Caddy)
  - database backups: Litestream replication to S3-compatible storage (the SQLite production path in `references/database.md`); do not use `django-dbbackup`
  - production Dockerfile: single-stage; install the Litestream `.deb`, ship `litestream.yml` + `entrypoint.sh` that restores the DB on boot, runs migrations, then execs `litestream replicate -exec "gunicorn ..."`
Skip GDPR for this case.

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `Caddyfile`, `litestream.yml`, `entrypoint.sh`, `.github/workflows/test.yml`. Do not actually push to a remote VPS — just verify all artifacts are present and `docker build .` succeeds.
```

## Boot check

```sh
cd 07-vps-sqlite-saas
docker compose up -d
docker compose exec -T web uv run manage.py migrate
docker compose exec -T web uv run manage.py createcachetable --database cache
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
uv run pyright
docker build -t 07-vps-sqlite-saas:test .
docker run --rm 07-vps-sqlite-saas:test which gunicorn
docker run --rm 07-vps-sqlite-saas:test which litestream
docker run --rm 07-vps-sqlite-saas:test id -un | grep -q '^django$'
! docker compose logs web 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
docker compose down -v --rmi local
docker rmi 07-vps-sqlite-saas:test
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,test}.py`, `config/routers.py`, `Dockerfile`, `Dockerfile.dev`, `docker-compose.yml`, `docker-compose.prod.yml`, `Caddyfile`, `litestream.yml`, `entrypoint.sh`, `mise.toml`, `.github/workflows/test.yml`, `.pre-commit-config.yaml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`.
- `mise.toml` has `[tasks.deploy-migrate]` running `docker compose -f docker-compose.prod.yml run --rm web uv run manage.py migrate` and `[tasks.deploy]` with `depends = ["deploy-migrate"]` running `docker compose -f docker-compose.prod.yml up -d`.
- `pyproject.toml` runtime deps include `django-environ`, `django-tasks`, `django-tasks-db`, `whitenoise`, `django-allauth[mfa]`, `django-axes`, `django-csp`, `sentry-sdk`, `structlog`, `django-structlog`, `gunicorn`. **No** `psycopg`, `celery`, `redis`, `django-dbbackup`. Dev deps include `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`, `ruff`, `pre-commit`.

**Settings split + SQLite mini-prod**
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`; `wsgi.py`/`asgi.py` to `config.settings.production`.
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`. `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `base.py` inside an `except ImportError: pass` guard.
- `production.py` sets `DATABASES["default"]["OPTIONS"]` with the SQLite mini-prod block: `transaction_mode = "IMMEDIATE"`, `timeout = 5`, and an `init_command` containing `PRAGMA journal_mode=WAL;`, `PRAGMA synchronous=NORMAL;`, `PRAGMA mmap_size=...`, `PRAGMA cache_size=...`.
- `base.py` defines `DATABASES["cache"]` (env-driven path, defaulting under `BASE_DIR`), `CACHES["default"]` using `django.core.cache.backends.db.DatabaseCache` with `LOCATION = "cache_table"`, and `DATABASE_ROUTERS = ["config.routers.CacheRouter"]`. `production.py` adds `DATABASES["cache"]["OPTIONS"] = DATABASES["default"]["OPTIONS"]`. Prod `.env` sets `CACHE_DB_PATH=/data/cache.sqlite3`.
- `config/routers.py` defines `CacheRouter` routing reads/writes/migrations for `app_label == "django_cache"` to the `cache` database.
- Security settings (`SECURE_SSL_REDIRECT`, HSTS, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `CSRF_TRUSTED_ORIGINS`, `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`) live in `production.py` only. `csp.middleware.CSPMiddleware` and `CONTENT_SECURITY_POLICY` in `production.py` only — not in `base.py`/`local.py`.
- `WhiteNoiseMiddleware` inserted directly after `SecurityMiddleware` in `MIDDLEWARE`.

**Custom user + auth + MFA**
- `users/models.py` defines `User` extending `AbstractUser`. `AUTH_USER_MODEL = "users.User"`. `users/migrations/0001_initial.py` exists.
- `INSTALLED_APPS` includes `allauth`, `allauth.account`, `allauth.mfa`, `django.contrib.sites`, `axes`. NOT `allauth_2fa` (deprecated).
- `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`.
- `accounts/` URL include in `config/urls.py` mounts both `allauth.urls` and `allauth.mfa.urls`. `MFA_SUPPORTED_TYPES` and `MFA_TOTP_ISSUER` defined. `ACCOUNT_REAUTHENTICATION_REQUIRED = True` in `production.py` only.

**Logging + Sentry + tasks**
- `structlog` configured in `base.py`. `LOGGING` at module scope. `django_structlog.middlewares.RequestMiddleware` in `MIDDLEWARE` directly after `AuthenticationMiddleware`. `django_structlog` in `INSTALLED_APPS`.
- `sentry_sdk.init(...)` called from `production.py` only; DSN read from env via the gated default.
- A registered Django app has `apps.py` with `ready()` importing `tasks`, and a `tasks.py` defining at least one `@task` (from `django_tasks`). `INSTALLED_APPS` includes `django_tasks` and `django_tasks_db`. `TASKS = {"default": {"BACKEND": "django_tasks_db.DatabaseBackend"}}` (or equivalent) in `base.py` or `production.py`.

**Deploy artefacts**
- `Dockerfile` is single-stage on `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`, with `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, two-step `uv sync`, `/app/.venv/bin` on PATH, runs as `django` user. Installs the Litestream `.deb` (`wget` + `dpkg -i litestream-v0.3.13-linux-amd64.deb`).
- `entrypoint.sh` runs `litestream restore -if-db-not-exists -if-replica-exists /data/site.sqlite3`, then `python manage.py migrate --noinput`, then `createcachetable --database cache`, then `exec litestream replicate -exec "gunicorn config.wsgi --bind 0.0.0.0:8000"`. `Dockerfile` `CMD` invokes `entrypoint.sh`.
- `litestream.yml` declares `dbs: [{path: /data/site.sqlite3, replicas: [{type: s3, ...}]}]` reading bucket/endpoint/keys from env.
- `Caddyfile` upstream block uses `health_uri /healthz` (liveness, not `/readyz`).
- `docker-compose.prod.yml` defines a single `web` service with `restart: unless-stopped`, mounts a named `sqlite_data:/data` volume, and a container-level healthcheck (python urllib, no curl). **No** `db`, `redis`, or `celery` services. Top-level `volumes:` declares `sqlite_data`.
- `docker-compose.yml` (dev) also mounts `sqlite_data:/data` on `web` and declares the volume at the top.
- `.env` / `.env.example` set `DATABASE_URL=sqlite:////data/site.sqlite3` and list the Litestream S3 env vars (`S3_BUCKET`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`).
- `.github/workflows/test.yml` runs migrations + pytest against SQLite (no Postgres/Redis services in the workflow). Env block ships `EMAIL_URL=consolemail://`, `DATABASE_URL=sqlite:///db.sqlite3`, `DJANGO_SECRET_KEY` placeholder, `DJANGO_DEBUG=False`.

**Health**
- `pages` app exposes `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
