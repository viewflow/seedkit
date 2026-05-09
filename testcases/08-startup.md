# 08 — Production: Fly.io managed deploy, multi-stage Dockerfile, GlitchTip, GDPR, GA4

Covers managed-platform deployment with a slim multi-stage image, S3 storage, GA4 analytics, GlitchTip error reporting, GDPR scaffolding, and CI.

## Prompt

```
/seedkit

Project name: 08-fly-app
Purpose: production app deployed to Fly.io with a slim multi-stage runtime image and S3-compatible object storage.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (web + db + redis + minio).
Docker structure: override (one multi-stage `Dockerfile` with `dev`/`prod` targets, `docker-compose.yml` + `docker-compose.override.yml`).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Add-ons:
  - redis
  - tasks: Celery
  - storage: S3-compatible (MinIO locally, real S3 in prod)
  - analytics: Google Analytics 4 (GA4)
  - email: anymail (Postmark provider). Install `django-anymail[postmark]`; set `EMAIL_BACKEND = "anymail.backends.postmark.EmailBackend"` only when not DEBUG; gate `POSTMARK_SERVER_TOKEN` from env. Wire `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`. Console backend stays as the `EMAIL_URL` fallback in dev. (django-mail-auth needs working email to send magic links.) Also include the Anymail webhook URL (`path("anymail/", include("anymail.urls"))`) and `ANYMAIL["WEBHOOK_SECRET"]`.
  - CORS: no.
  - REST API: `django-bolt` **with fast-path settings opt-in** (`uv add django-bolt`). Add `django_bolt` to `INSTALLED_APPS` in `base.py`. Create `config/settings/bolt.py` that imports from `base` and strips `SessionMiddleware`, `MessageMiddleware`, `CsrfViewMiddleware`, `AuthenticationMiddleware`, `WhiteNoiseMiddleware` from `MIDDLEWARE` and `django.contrib.admin`, `django.contrib.sessions`, `django.contrib.messages`, `django.contrib.staticfiles` from `INSTALLED_APPS`; sets `TEMPLATES = []` and `ROOT_URLCONF = 'config.urls_bolt'`. Create `config/urls_bolt.py` (API-only; no admin / accounts). Create an `api` app (`uv run manage.py startapp api`) with `api/api.py` exposing `BoltAPI()`, a single `GET /users/{user_id}` async handler returning a `msgspec.Struct` (`id`, `username`) populated via `await User.objects.aget(id=user_id)`. `runserver`/`gunicorn` keep using `config.settings.local` / `production`; `runbolt` runs against `config.settings.bolt`.
  - Frontend: none.
  - Auth hardening: `django-axes` (yes), 2FA (no).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings
  - CSP via `django-csp`: yes
  - error reporting: GlitchTip via sentry-sdk
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete views
  - CI: GitHub Actions test workflow
  - deploy target: Fly.io managed (use `[processes]` for web + worker + bolt; the `bolt` process runs `manage.py runbolt` with `DJANGO_SETTINGS_MODULE=config.settings.bolt`)
  - production Dockerfile: multi-stage (builder + slim runtime)

Run the foundation + boot check locally. Generate `Dockerfile`, `fly.toml`, `.github/workflows/test.yml`. Verify `docker build .` succeeds and the runtime stage uses `python:3.12-slim-bookworm`.
```

## Expected outcome

- Local `docker compose up -d` starts web + db + redis + worker + minio; `/admin/` login works.
- Production Dockerfile has two stages: `builder` (uv image) → `runtime` (`python:3.12-slim-bookworm`); only `/app/.venv` and project source copied into runtime.
- `docker build .` succeeds; final image notably smaller than 07 (`docker images` size diff).
- `fly.toml` has `[processes]` with `web = "gunicorn ..."`, `worker = "celery ..."`, and `bolt = "python manage.py runbolt ..."`. The `bolt` process sets `DJANGO_SETTINGS_MODULE=config.settings.bolt` (via `[env]` block or inline); `web` keeps `config.settings.production`.
- `django-bolt` in dependencies; `django_bolt` in `INSTALLED_APPS` (`base.py`).
- `config/settings/bolt.py` exists and, after import, `MIDDLEWARE` excludes the five stripped middleware classes; `INSTALLED_APPS` excludes admin / sessions / messages / staticfiles; `TEMPLATES == []`; `ROOT_URLCONF == 'config.urls_bolt'`.
- `config/urls_bolt.py` exists and does NOT import `django.contrib.admin` or the accounts URLConf.
- `api/api.py` defines `api = BoltAPI()` and a `@api.get("/users/{user_id}")` async handler returning a `msgspec.Struct`.
- `manage.py runbolt --dev` boots without raising; `curl http://127.0.0.1:<bolt-port>/users/<id>` returns the seeded user as JSON.
- GlitchTip wired via `sentry-sdk` in `production.py`, DSN from env.
- GDPR scaffolding present: `before_send` PII scrubber, `data_export` / `data_delete` views or management commands.
- GA4 snippet in base template, measurement ID from env.
- Security settings + CI workflow present.
- `django-mail-auth` installed; `mailauth` in `INSTALLED_APPS`; `MailAuthBackend` in `AUTHENTICATION_BACKENDS`; `accounts/` URL include with `mailauth` namespace; `/accounts/login/` renders an email-only form.
- `django-axes` installed; `axes` in `INSTALLED_APPS`; `AxesMiddleware` last in `MIDDLEWARE`; `AxesBackend` first in `AUTHENTICATION_BACKENDS`. `AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'` set in `production.py` (Redis is required and present). `axes_*` migrations applied.
- `django-csp` installed; `csp.middleware.CSPMiddleware` in `production.py` `MIDDLEWARE`. `CONTENT_SECURITY_POLICY['DIRECTIVES']['script-src']` includes both `https://www.googletagmanager.com` and `https://www.google-analytics.com`. `connect-src` and `img-src` include `https://www.google-analytics.com`. No `'unsafe-inline'` in `script-src`.
- `pages` app exposes `liveness` / `readiness`; `urlpatterns` wires `path('healthz', ...)` and `path('readyz', ...)`. `fly.toml` `[checks]` block has at least one entry with `path = "/readyz"` and `interval = "10s"`. `curl /healthz` against the local Compose stack returns 200 `ok`.

## Run

```sh
# Run from a scratch parent dir; the skill creates `08-fly-app/`.
# AI executes the skill here, then:
cd 08-fly-app
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
# Healthchecks reachable via the standard Django process
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Fly.io [checks] block points at /readyz
grep -E '^\s*path\s*=\s*"/readyz"' fly.toml
# CSP enforced and includes GA4 hosts
grep -q 'csp.middleware.CSPMiddleware' config/settings/production.py
grep -q 'googletagmanager.com' config/settings/production.py
# Bolt fast-path: smoke-check the slim settings load + endpoint serves
docker compose exec -e DJANGO_SETTINGS_MODULE=config.settings.bolt web \
  uv run python -c "from django.conf import settings; \
    assert 'django.contrib.admin' not in settings.INSTALLED_APPS, settings.INSTALLED_APPS; \
    assert settings.ROOT_URLCONF == 'config.urls_bolt', settings.ROOT_URLCONF; \
    assert settings.TEMPLATES == [], settings.TEMPLATES"
# Boot runbolt in the background and curl the user endpoint (uses superuser id=1)
docker compose exec -d -e DJANGO_SETTINGS_MODULE=config.settings.bolt web \
  uv run manage.py runbolt --dev
sleep 2
docker compose exec web sh -c 'curl -sf http://127.0.0.1:8001/users/1' || true
docker build -t 08-fly-app:test .
docker images 08-fly-app:test
```

## Log check

Run after the boot check; the testcase is a failure if any of these print matches:

```sh
docker compose logs --tail=80 web worker db redis minio
! docker compose logs web worker 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
docker compose logs worker 2>&1 | grep -iE 'celery@.*ready|mingle|sync with'
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Audit the existing code in this directory. The following are INTENTIONAL design decisions of the seedkit skill — do NOT flag them as bugs even if they look unusual: (a) `default=... if DEBUG else None` gated defaults on SECRET_KEY / DATABASES (fail-fast in prod, zero-config in dev/build); (b) `globals().update(env.email_url(...))` is the documented django-environ idiom for spreading email settings; (c) `local.py` containing only `from .base import *` (deltas-only design; all dev defaults live in base via env vars); (d) WhiteNoise `STORAGES` configured only in `production.py`, never base (manifest storage requires collectstatic, breaks runserver); (e) `wsgi.py` / `asgi.py` defaulting to `config.settings.production` while `manage.py` defaults to `local` (intentional safety asymmetry); (f) custom user model with `username = None`, `email` as `USERNAME_FIELD`, and a custom `UserManager` when email-only auth is chosen; (g) `ACCOUNT_EMAIL_VERIFICATION = \"optional\"` in base, `\"mandatory\"` in production.py. Skip these in the report. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content. Focus on configuration correctness, security, deployment readiness, and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, or domain models. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially seedkit). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code. Tear down local containers and the built image. If you ran `flyctl launch` for real, also `fly apps destroy 08-fly-app` and revoke any tokens; otherwise nothing to undo on Fly.io.

```sh
docker compose down -v
docker rmi 08-fly-app:test
```
