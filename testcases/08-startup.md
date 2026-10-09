# 08 — Production: Fly.io managed deploy, multi-stage Dockerfile, GlitchTip, GDPR, GA4

Covers managed-platform deployment with a slim multi-stage image, S3 storage, GA4 analytics, GlitchTip error reporting, GDPR scaffolding, and CI.

## Prompt

```
/django-seedkit

Project name: 08-fly-app
Purpose: production app deployed to Fly.io with a slim multi-stage runtime image and S3-compatible object storage.

Settings layout: split.
Database: PostgreSQL.
Postgres location: Postgres-in-Docker (`db` service alongside `redis` and `minio` in `docker-compose.yml`, port `127.0.0.1:5432` published).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Task runner: mise.
Add-ons:
  - redis
  - tasks: Celery
  - storage: S3-compatible (MinIO locally, real S3 in prod)
  - analytics: Google Analytics 4 (GA4)
  - email: anymail (Postmark provider). Install `django-anymail[postmark]`; set `MAILERS["default"]` to `anymail.backends.postmark.EmailBackend` only when not DEBUG; gate `POSTMARK_SERVER_TOKEN` from env. Wire `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`. The default mailer stays on Django's console backend in dev. (django-mail-auth needs working email to send magic links.) Also include the Anymail webhook URL (`path("anymail/", include("anymail.urls"))`) and `ANYMAIL["WEBHOOK_SECRET"]`.
  - HTML email base template: no.
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
  - CSP using Django's built-in CSP support: yes
  - error reporting: GlitchTip via sentry-sdk
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete views
  - CI: GitHub Actions test workflow
  - deploy target: Fly.io managed (use `[processes]` for web + worker + bolt; the `bolt` process runs `manage.py runbolt` with `DJANGO_SETTINGS_MODULE=config.settings.bolt`)
  - production Dockerfile: multi-stage (builder + slim runtime)

Run the foundation + boot check locally. Generate `Dockerfile`, `fly.toml`, `.github/workflows/test.yml`. Verify `docker build .` succeeds and the runtime stage uses `python:3.13-slim-trixie`.
```

## Boot check

Run the checks in order. Before starting processes or services, wrap the shell blocks in a cleanup script that records child PIDs and resources created by this run and removes them on success or failure. Use a unique Compose project name. For host Postgres, reuse only a database created during this case's foundation step; fail if an unrelated database already has the requested name. Later acceptance subsections run from this project's root.

```sh
set -eu
cd 08-fly-app
docker compose up -d --wait             # db + redis + minio
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
DJANGO_SETTINGS_MODULE=config.settings.local uv run celery -A config worker -l info &
WORKER_PID=$!
up=
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "${up:-}" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID" "$WORKER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
DJANGO_SETTINGS_MODULE=config.settings.bolt uv run python -c "
from django.conf import settings
assert 'django.contrib.admin' not in settings.INSTALLED_APPS
assert settings.ROOT_URLCONF == 'config.urls_bolt'
assert settings.TEMPLATES == []
"
DJANGO_SETTINGS_MODULE=config.settings.bolt uv run manage.py runbolt --dev --port 8001 &
BOLT_PID=$!
API_USER_ID=$(uv run manage.py shell -c "from django.contrib.auth import get_user_model; print(get_user_model().objects.get_or_create(username='bolt-smoke')[0].pk)" | tail -n 1)
api_up=
for i in 1 2 3 4 5; do curl -sf "http://127.0.0.1:8001/users/$API_USER_ID" > /tmp/seedkit-bolt-$$.json && api_up=1 && break; sleep 1; done
[ -n "$api_up" ] || { echo "BOOT CHECK FAILED: Bolt endpoint unavailable"; exit 1; }
uv run python -c "import json; from pathlib import Path; p=Path('/tmp/seedkit-bolt-$$.json'); data=json.loads(p.read_text()); assert data['id'] == int('$API_USER_ID') and data['username'] == 'bolt-smoke'; p.unlink()"
if rg -q 'django-csp' pyproject.toml; then
  echo "SMOKE CHECK FAILED: forbidden configuration or error output" >&2
  exit 1
fi
rg -q 'django.middleware.csp.ContentSecurityPolicyMiddleware' config/settings/production.py
rg -q 'SECURE_CSP' config/settings/production.py
rg -q 'CSP.NONCE' config/settings/production.py
rg -q 'django.template.context_processors.csp' config/settings/production.py
rg -q 'nonce="{{ csp_nonce }}"' templates/_analytics.html
uv run pyright
docker build --target prod -t 08-fly-app:test .
docker run --rm 08-fly-app:test python --version | grep -q '3\.13'
docker run --rm 08-fly-app:test sh -c 'if command -v uv; then exit 1; fi'
kill "$RUNSERVER_PID" "$WORKER_PID" "$BOLT_PID"
docker compose down -v
docker rmi 08-fly-app:test
```

### Production acceptance

Exercise `fly.toml` locally against disposable Postgres, Redis, and MinIO services. No Fly account or remote deploy is needed for this case; report the result as a local production check, not a verified Fly deployment.

1. Build the production image and create the test bucket. Run the exact `[deploy].release_command` parsed from `fly.toml`, using the image's entrypoint and production env. Require exit 0, applied migrations, and a known admin static object in the bucket. Supply every required env var, including S3 and Anymail placeholders; never send mail to Postmark or errors to GlitchTip.
2. Start the generated web, worker, and Bolt process commands from that image. Require web readiness using the configured healthcheck path and Host header. Create a test user, request it through Bolt, and assert the returned id and username. Require an unknown user to produce a client error rather than a traceback/500.
3. Save, read, and delete known bytes through Django's configured media storage. Assert the backend is S3 and the object exists in the disposable bucket; a local-filesystem fallback fails the check. Fetch an admin asset using the URL produced by static storage.
4. Run all generated CI `run:` steps with job/step env and local service addresses, including the production settings check. Require collected tests and exit 0.

Bind published ports to loopback, use bounded polls, and register cleanup for this run's containers, network, volumes, and image before starting them. Do not alter application settings or the release command just for the smoke check.

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,bolt,test}.py`, `config/urls.py`, `config/urls_bolt.py`, `Dockerfile` (multi-stage), `docker-compose.yml` (local services only — `db`, `redis`, `minio`; no `web` / `worker`), `fly.toml`, `mise.toml`, `.github/workflows/test.yml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`. No `Dockerfile.dev`, no `docker-compose.override.yml`.
- `mise.toml` has `[tasks.deploy]` running `fly deploy`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `celery[redis]` (or `celery` + `redis`), `django-storages[s3]`, `django-mail-auth`, `django-axes`, `django-bolt`, `msgspec`, `django-anymail[postmark]`, `sentry-sdk`, `gunicorn`. **No** `django-csp`. Dev deps include `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`, `ruff`.

**Settings (split + bolt)**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`. `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `base.py` inside an `except ImportError: pass` guard.
- `config/settings/bolt.py` imports from `base` and strips `SessionMiddleware`, `MessageMiddleware`, `CsrfViewMiddleware`, `AuthenticationMiddleware`, `WhiteNoiseMiddleware` from `MIDDLEWARE`, and `django.contrib.admin`, `django.contrib.sessions`, `django.contrib.messages`, `django.contrib.staticfiles` from `INSTALLED_APPS`. Sets `TEMPLATES = []` and `ROOT_URLCONF = "config.urls_bolt"`.
- `config/urls_bolt.py` contains `urlpatterns: list = []` (BoltAPI auto-discovers; no `.urls` to mount). Does NOT import `django.contrib.admin` or `accounts`.
- Security settings in `production.py` only, including `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`.
- `django.middleware.csp.ContentSecurityPolicyMiddleware` in `production.py`'s `MIDDLEWARE` only. `SECURE_CSP["script-src"]` includes `CSP.NONCE`, `https://www.googletagmanager.com`, and `https://www.google-analytics.com`; `django.template.context_processors.csp` is configured. `connect-src` and `img-src` include `https://www.google-analytics.com`. No `CSP.UNSAFE_INLINE` in `script-src`.

**Bolt API**
- `api/api.py` defines `api = BoltAPI()` and a `@api.get("/users/{user_id}")` async handler returning a `msgspec.Struct` populated via `await User.objects.aget(id=user_id)`.
- `INSTALLED_APPS` in `base.py` includes `django_bolt`.

**Auth + analytics + GDPR + Sentry**
- `INSTALLED_APPS` lists `mailauth.contrib.admin` BEFORE `django.contrib.admin`. `MailAuthBackend` in `AUTHENTICATION_BACKENDS`. `accounts/` URL include with `mailauth` namespace.
- `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`. `AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'` set in `production.py`.
- GA4 snippet in `templates/_analytics.html` (or equivalent) uses `{{ ANALYTICS_ID }}` and `nonce="{{ csp_nonce }}"`; it is included from `templates/base.html`.
- `sentry_sdk.init(...)` called from `production.py` only with `before_send` PII scrubber, `send_default_pii=False`.
- GDPR scaffolding present: `data_export` / `data_delete` views or management commands.

**Deploy artefacts**
- `Dockerfile` is multi-stage and pins `--platform=linux/amd64` on both stages so uv installs django-bolt's published `manylinux2014_x86_64` wheel (no `build-essential`, no source compile — there is no aarch64-linux wheel). `builder` runs `uv sync` on a `ghcr.io/astral-sh/uv:python3.13-trixie-slim` image; final `prod` stage uses `python:3.13-slim-trixie` with `/opt/venv/bin` on PATH and no uv binary.
- `fly.toml` has `[processes]` with `web`, `worker`, `bolt`. The `bolt` process sets `DJANGO_SETTINGS_MODULE=config.settings.bolt`. `[env]` sets `PORT` and `DJANGO_BEHIND_PROXY=True`. `DJANGO_ALLOWED_HOSTS` / `DJANGO_SECRET_KEY` / `DATABASE_URL` go via `fly secrets set` per `deploy-managed.md` — do not hardcode in `[env]`. `[deploy] release_command` runs both migrations and S3 `collectstatic` with shell handling for `&&` (not `uv run` — the slim runtime has no uv). `[[checks]]` (or service health) hits `/readyz`.
- `[checks]` / `[services.checks]` block in `fly.toml` references `/readyz`.

**Health**
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.
- Anymail webhook URL `path("anymail/", include("anymail.urls"))` wired; `ANYMAIL["WEBHOOK_SECRET"]` set.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
