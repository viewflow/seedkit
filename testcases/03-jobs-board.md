# 03 — Postgres-in-Docker, Django on host, Celery + Beat

Covers the "Postgres in Docker, Django on host" hybrid mode, plus Redis-backed Celery with periodic tasks.

## Prompt

```
/seedkit

Project name: 03-jobs-board
Purpose: job board with background email notifications and a daily digest.

Settings layout: single file.
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: run only Postgres in Docker, Django runs on the host (publish 5432 to localhost).
Lint with Ruff: no.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): yes.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Add-ons:
  - redis (for Celery)
  - tasks: Celery, with periodic tasks (Celery Beat)
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.

Production setup: skip.

Ship a `docker-compose.yml` with `db` and `redis` services only. Run the foundation, start the containers, run migrate + createsuperuser, and define one trivial Celery task plus one Beat-scheduled task to prove autodiscovery works.
```

## Boot check

```sh
cd 03-jobs-board
docker compose up -d
docker compose ps
uv run manage.py migrate
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Confirm Celery autodiscovers without holding the worker open:
uv run python -c "from config import celery_app; print(sorted(celery_app.tasks))"
# docker logs must not contain fatal errors:
! docker compose logs db redis 2>&1 | grep -iE 'fatal|panic|traceback'
kill $(jobs -p) 2>/dev/null; pkill -f 'manage.py' 2>/dev/null; wait
docker compose down -v
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings.py` (single-file), `config/celery.py`, `config/__init__.py`, `docker-compose.yml`, `.env`, `.env.example`, `.gitignore`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `celery[redis]` (or `celery` + `redis`), `django-mail-auth`, `django-redis`. No `ruff`, no `pyright`.
- `.env` sets `DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres` and `REDIS_URL=redis://localhost:6379/0`.
- `docker-compose.yml` defines services `db` (postgres) and `redis` only — no `web`, no `worker`. Both ports published to localhost.

**Settings**
- `config/settings.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True` set.
- `CELERY_BROKER_URL` and `CELERY_RESULT_BACKEND` derived from `REDIS_URL`.
- `LANGUAGES`, `LOCALE_PATHS`, `LocaleMiddleware` configured (i18n=yes).

**Celery**
- `config/celery.py` defaults `DJANGO_SETTINGS_MODULE` to the production module (mirrors wsgi/asgi). For the single-file layout this is `config.settings`.
- `config/__init__.py` exposes `celery_app`.
- A registered Django app (e.g. `jobs/`) ships `tasks.py` with at least one `@shared_task` (or `@task`) function. `CELERY_BEAT_SCHEDULE` references one of those tasks.

**Auth (mail-auth)**
- `INSTALLED_APPS` lists `mailauth.contrib.admin` BEFORE `django.contrib.admin`, plus `mailauth`. `AUTHENTICATION_BACKENDS` includes `mailauth.backends.MailAuthBackend`.
- `config/urls.py` includes `mailauth.urls` under `accounts/` with the `mailauth` namespace. `/accounts/login/` route resolves.
- Templates under `templates/registration/` exist for the magic-link UI.

**Health checks**
- `pages/views.py` (or equivalent) defines `liveness` and `readiness`. `urlpatterns` wires `path('healthz', ...)` and `path('readyz', ...)` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
