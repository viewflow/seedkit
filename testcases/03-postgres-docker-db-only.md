# 03 — Postgres-in-Docker, Django on host, Celery + Beat

Covers the "Postgres in Docker, Django on host" hybrid mode, plus Redis-backed Celery with periodic tasks.

## Prompt

```
/cookiecutter

Project name: 03-jobs-board
Purpose: job board with background email notifications and a daily digest.

Settings layout: single file.
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: run only Postgres in Docker, Django runs on the host (publish 5432 to localhost).
Lint with Ruff: no.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Add-ons:
  - redis (for Celery)
  - tasks: Celery, with periodic tasks (Celery Beat)
Production setup: skip.

Ship a `docker-compose.yml` with `db` and `redis` services only. Run the foundation, start the containers, run migrate + createsuperuser, and define one trivial Celery task plus one Beat-scheduled task to prove autodiscovery works.
```

## Expected outcome

- `docker compose up -d db redis` starts both containers; `pg_isready` and `redis-cli ping` succeed.
- `uv run manage.py runserver` boots on host; `/admin/` login works.
- `.env` has `DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres` and `REDIS_URL=redis://localhost:6379/0`.
- `uv run celery -A config worker -l info` starts; example task can be enqueued from a `manage.py shell` and runs.
- `uv run celery -A config beat -l info` starts without errors and lists the example schedule.
- `CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True` is set.
- `django-mail-auth` installed; `mailauth` in `INSTALLED_APPS`; `MailAuthBackend` listed in `AUTHENTICATION_BACKENDS`; `accounts/` URL include with `mailauth` namespace; `/accounts/login/` renders an email-only form.

## Run

```sh
# Run from a scratch parent dir; the skill creates `03-jobs-board/`.
# AI executes the skill here, then:
cd 03-jobs-board
docker compose up -d
uv run manage.py runserver &
uv run celery -A config worker -l info &
uv run celery -A config beat -l info &
# enqueue + observe one task
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Audit the existing code in this directory. The following are INTENTIONAL design decisions of the cookiecutter skill — do NOT flag them as bugs even if they look unusual: (a) `default=... if DEBUG else None` gated defaults on SECRET_KEY / DATABASES (fail-fast in prod, zero-config in dev/build); (b) `globals().update(env.email_url(...))` is the documented django-environ idiom for spreading email settings; (c) `local.py` containing only `from .base import *` (deltas-only design; all dev defaults live in base via env vars); (d) WhiteNoise `STORAGES` configured only in `production.py`, never base (manifest storage requires collectstatic, breaks runserver); (e) `wsgi.py` / `asgi.py` defaulting to `config.settings.production` while `manage.py` defaults to `local` (intentional safety asymmetry); (f) custom user model with `username = None`, `email` as `USERNAME_FIELD`, and a custom `UserManager` when email-only auth is chosen; (g) `ACCOUNT_EMAIL_VERIFICATION = \"optional\"` in base, `\"mandatory\"` in production.py. Skip these in the report. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content, AND no production hardening (no security settings, error reporting, GDPR, CI, deploy config, or production Dockerfile). Focus on configuration correctness for the dev/foundation scope and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, domain models, or production-only settings — those are out of scope for this case. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially cookiecutter). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code. Tear down containers and volumes:

```sh
docker compose down -v
```
