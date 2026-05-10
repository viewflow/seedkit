# 07 — Production: VPS deploy, single-stage Dockerfile, Sentry

Covers full production path on a VPS with Caddy, single-stage Dockerfile, security settings, Sentry SaaS error reporting, GitHub Actions test CI, and Celery in prod.

## Prompt

```
/seedkit

Project name: 07-vps-saas
Purpose: production-ready SaaS skeleton deployed to a single VPS via docker-compose + Caddy.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (full stack: web + db + redis).
Docker structure: simple (separate `Dockerfile.dev` for dev, single-stage production `Dockerfile`).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: yes.
Internationalisation (i18n): no.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login + mandatory verification).
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Add-ons:
  - redis
  - tasks: Celery (no Beat)
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
  - database backups via `django-dbbackup`: yes
  - production Dockerfile: single-stage
Skip GDPR for this case.

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `Caddyfile`, `.github/workflows/test.yml`. Do not actually push to a remote VPS — just verify all artifacts are present and `docker build .` succeeds.
```

## Boot check

```sh
cd 07-vps-saas
docker compose up -d
docker compose exec -T web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
uv run pyright
docker build -t 07-vps-saas:test .
docker run --rm 07-vps-saas:test which gunicorn
docker run --rm 07-vps-saas:test id -un | grep -q '^django$'
! docker compose logs web celery 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
docker compose logs celery 2>&1 | grep -iE 'celery@.*ready|mingle|sync with'
docker compose down -v
docker rmi 07-vps-saas:test
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,test}.py`, `Dockerfile`, `Dockerfile.dev`, `docker-compose.yml`, `docker-compose.prod.yml`, `Caddyfile`, `.github/workflows/test.yml`, `.pre-commit-config.yaml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `celery[redis]` (or `celery` + `redis`), `whitenoise`, `django-allauth[mfa]`, `django-axes`, `django-csp`, `django-dbbackup`, `django-storages[s3]`, `sentry-sdk`, `structlog`, `gunicorn`. Dev deps include `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`, `ruff`, `pre-commit`.

**Settings split**
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`; `wsgi.py`/`asgi.py` to `config.settings.production`.
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`. `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `base.py` inside an `except ImportError: pass` guard.
- Security settings (`SECURE_SSL_REDIRECT`, HSTS, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `CSRF_TRUSTED_ORIGINS`, `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`) live in `production.py` only. `csp.middleware.CSPMiddleware` and `CONTENT_SECURITY_POLICY` in `production.py` only — not in `base.py`/`local.py`.
- `WhiteNoiseMiddleware` inserted directly after `SecurityMiddleware` in `MIDDLEWARE`.

**Custom user + auth + MFA**
- `users/models.py` defines `User` extending `AbstractUser`. `AUTH_USER_MODEL = "users.User"`. `users/migrations/0001_initial.py` exists.
- `INSTALLED_APPS` includes `allauth`, `allauth.account`, `allauth.mfa`, `django.contrib.sites`, `axes`. NOT `allauth_2fa` (deprecated).
- `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`.
- `accounts/` URL include in `config/urls.py` mounts both `allauth.urls` and `allauth.mfa.urls`. `MFA_SUPPORTED_TYPES` and `MFA_TOTP_ISSUER` defined. `ACCOUNT_REAUTHENTICATION_REQUIRED = True` in `production.py` only.

**Logging + Sentry**
- `structlog` configured in `base.py`. `LOGGING` at module scope. `RequestContextMiddleware` in `MIDDLEWARE` after `AuthenticationMiddleware`, emits one log line per request.
- `sentry_sdk.init(...)` called from `production.py` only; DSN read from env via the gated default.

**Deploy artefacts**
- `Dockerfile` is single-stage on `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`, with `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, two-step `uv sync`, `/app/.venv/bin` on PATH, runs as `django` user.
- `Caddyfile` upstream block uses `health_uri /healthz` (liveness, not `/readyz`).
- `docker-compose.prod.yml` has services `web`, `db`, `redis`, `celery` with `restart: unless-stopped`. `web` has a container-level healthcheck (python urllib, no curl).
- `.github/workflows/test.yml` runs migrations + pytest against a Postgres service. Env block ships `EMAIL_URL=consolemail://`, `REDIS_URL=redis://localhost:6379`, `DJANGO_SECRET_KEY` placeholder, `DJANGO_DEBUG=False`.
- `dbbackup` block in `production.py` is gated `if not DEBUG:` — INSTALLED_APPS entry, `DBBACKUP_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"`, `DBBACKUP_STORAGE_OPTIONS`. `DBBACKUP_BUCKET` listed in `.env.example`.

**Health**
- `pages` app exposes `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
