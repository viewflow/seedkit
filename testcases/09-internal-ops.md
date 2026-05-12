# 09 — Production: GitHub Actions SSH deploy, Bugsink, Umami, Django Tasks (RQ)

Covers the GitHub-Actions-over-SSH deploy path, self-hosted Bugsink for error reporting, Umami analytics, Django Tasks with the Redis Queue backend, GDPR scaffolding, and CI.

## Prompt

```
/seedkit

Project name: 09-ssh-deploy
Purpose: production app deployed to a remote host over SSH from GitHub Actions, using self-hosted services.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (web + db + redis).
Docker structure: override (one multi-stage `Dockerfile` with `dev`/`prod` targets, `docker-compose.yml` + `docker-compose.override.yml`).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Task runner: mise.
Add-ons:
  - redis
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`). Also `uv run manage.py startapp jobs`, register `jobs` in `INSTALLED_APPS`, wire `jobs/apps.py` `ready()` to import `tasks`, and add a sample `@task` to `jobs/tasks.py`.
  - analytics: Umami (self-hosted, env-driven website ID and host)
  - email: none (deliberately skip `references/email.md`; this project does not send transactional mail and the test verifies the skip path).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings
  - CSP via `django-csp`: yes
  - error reporting: Bugsink (self-hosted, sentry-sdk DSN)
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete
  - CI: GitHub Actions test workflow
  - deploy: GitHub Actions deploy via SSH (rsync + remote `docker compose pull && up -d`)
  - database backups via `django-dbbackup`: yes (self-managed host — no native backup service)
  - production Dockerfile: single-stage (small enough; multi-stage not needed)

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `.github/workflows/test.yml`, `.github/workflows/deploy.yml`. Do not actually deploy — verify all artifacts are present, `docker build .` succeeds, and the deploy workflow references `secrets.SSH_HOST`, `secrets.SSH_USER`, `secrets.SSH_KEY`.
```

## Boot check

```sh
cd 09-ssh-deploy
docker compose up -d
docker compose exec -T web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
docker build -t 09-ssh-deploy:test .
! docker compose logs web worker 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
docker compose logs worker 2>&1 | grep -iE 'rqworker|listening on|default'
docker compose down -v --rmi local
docker rmi 09-ssh-deploy:test
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,test}.py`, `Dockerfile`, `docker-compose.yml`, `docker-compose.override.yml`, `deploy/docker-compose.prod.yml`, `deploy/.env.prod.example`, `mise.toml`, `.github/workflows/{test.yml,deploy.yml}`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`.
- `mise.toml` has `[tasks.deploy-migrate]` and `[tasks.deploy]` (with `depends = ["deploy-migrate"]`) targeting `deploy/docker-compose.prod.yml`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tasks-rq`, `django-rq`, `django-csp`, `django-dbbackup`, `django-storages[s3]` (or `boto3`), `sentry-sdk`, `structlog`, `django-structlog`, `gunicorn`. (`django.tasks` is built into Django 6 — no separate `django-tasks` package.) Dev deps include `pytest`, `pytest-django`, `ruff`.
- `pyproject.toml` does NOT list `django-axes`, `django-allauth`, `django-mail-auth`, or anymail/email packages — auth = none, email = none.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- Security settings (`SECURE_SSL_REDIRECT`, HSTS, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `CSRF_TRUSTED_ORIGINS`, `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`) live in `production.py` only.
- `csp.middleware.CSPMiddleware` and `CONTENT_SECURITY_POLICY` in `production.py` only. `script-src` includes the Umami host (resolved from env at runtime). No `'unsafe-inline'` in `script-src`.
- `INSTALLED_APPS` in `base.py` does NOT contain `axes`, `allauth`. `dbbackup` is added only inside the `if not DEBUG:` block in `production.py`.
- `production.py` `if not DEBUG:` block adds `dbbackup` to `INSTALLED_APPS`, sets `DBBACKUP_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"` and `DBBACKUP_STORAGE_OPTIONS` reading bucket/key/secret from env. `DBBACKUP_BUCKET` listed in `.env.example`.

**Tasks**
- `INSTALLED_APPS` includes `django_rq` and `django_tasks_rq`. `RQ_QUEUES` defined; top-level `RQ = {"JOB_CLASS": "django_tasks_rq.Job"}`.
- A registered Django app has `apps.py` with `ready()` importing `tasks`, and a `tasks.py` defining at least one `@task`.
- `docker-compose.yml` (or override) defines a `worker` service running `manage.py rqworker default`.

**Logging + Sentry/Bugsink**
- `structlog` configured in `base.py`. `LOGGING` at module scope. `django_structlog.middlewares.RequestMiddleware` in `MIDDLEWARE` directly after `AuthenticationMiddleware`. `django_structlog` in `INSTALLED_APPS`.
- `sentry_sdk.init(...)` called from `production.py` only with `before_send` PII scrubber, `send_default_pii=False`. DSN read from env.

**Analytics + GDPR**
- Umami snippet in `templates/_analytics.html` (or equivalent), gated on `ANALYTICS_ID` and `ANALYTICS_HOST` from a context processor. Included from `templates/base.html`.
- GDPR scaffolding: `data_export` / `data_delete` views or management commands present.

**Deploy artefacts**
- `deploy/.env.prod.example` ships every var the prod compose references, including `DJANGO_SETTINGS_MODULE=config.settings.production`, `DJANGO_ALLOWED_HOSTS=example.com,localhost,127.0.0.1` (localhost+127.0.0.1 for the in-container healthcheck), `DJANGO_BEHIND_PROXY=True`, `POSTGRES_PASSWORD`, `GITHUB_REPOSITORY`.
- `.github/workflows/deploy.yml` uses `secrets.SSH_HOST`, `secrets.SSH_USER`, `secrets.SSH_KEY`, `secrets.GHCR_TOKEN`. The SSH script `export GITHUB_REPOSITORY="${{ github.repository }}"` before `compose pull`. Every `docker compose` invocation passes `--env-file deploy/.env.prod`. `concurrency: group: deploy` set.
- `docker/build-push-action` step has `target: prod` (multi-stage override layout).
- The container healthcheck in `deploy/docker-compose.prod.yml` uses python urllib (no curl dependency).
- `.github/workflows/test.yml` runs migrations + pytest. Env block ships `EMAIL_URL=consolemail://`, `REDIS_URL=redis://localhost:6379`, `DJANGO_SECRET_KEY` placeholder, `DJANGO_DEBUG=False`.

**Health**
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
