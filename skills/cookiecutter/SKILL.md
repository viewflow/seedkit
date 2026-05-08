---
name: cookiecutter
description: Set up a new Django project with only the components you need.
---

## Prerequisites

```sh
uv --version
```

## Reference files

### Project foundation

- `references/uv.md` — uv installation and commands
- `references/new-project.md` — new project (Two Scoops layout, django-environ, uv)
- `references/database.md` — SQLite vs PostgreSQL (host or Docker)
- `references/docker.md` — local docker-compose dev + production image
- `references/lint.md` — Ruff (Django-aware rules, optional pre-commit hook)

### Add-ons

- `references/debug.md` — dev debug dashboard: django-orbit (observability, MCP) or django-silk (profiling + `@silk_profile`); ask the user which one
- `references/redis.md` — Redis cache (django-redis)
- `references/storage-whitenoise.md` — static files (WhiteNoise) + media volume on VPS
- `references/storage-s3.md` — static and media on S3-compatible storage
- `references/tasks-celery.md` — background tasks with Celery + Redis
- `references/tasks-django.md` — background tasks with Django Tasks (DB or RQ backend)
- `references/email.md` — transactional email (console in dev, SMTP in prod, optional Mailpit)
- `references/analytics.md` — site analytics (GoatCounter / Umami / Shynet / GA4)

### Going to production

- `references/security.md` — Django security settings
- `references/error-reporting.md` — exception tracking (Bugsink / Sentry SaaS / GlitchTip via sentry-sdk)
- `references/gdpr.md` — PII scrubbing, data residency, retention, user data export/delete
- `references/ci.md` — GitHub Actions test workflow
- `references/deploy-vps.md` — VPS deploy with Docker + Caddy
- `references/deploy-managed.md` — Fly.io / Railway / Render
- `references/deploy-github-ssh.md` — GitHub Actions deploy via SSH

## Instructions

### 1. Overview first

Before any question, send one short message that summarises — in your own words, generated from the **Reference files** list above — what this skill can set up: the foundation, the add-ons, and the production options. Do not paste a fixed template; phrase it fresh each time. End by inviting the user to begin.

### 2. Foundation — ask one question at a time, in this order

1. Project name and a one-line purpose.
2. Settings layout: single `settings.py` or split `base/local/production`.
3. Database: **SQLite** (zero-setup) or **PostgreSQL**.
4. Local dev mode: **uv on host** or **docker-compose**.
   - Postgres + uv-on-host → ask: create a local Postgres DB on the host, or run only Postgres in Docker while Django runs on the host.
   - docker-compose → full stack in Compose.
   - SQLite + Docker is allowed but warn the file lives in a container volume.
5. Lint with Ruff: yes / no.

Never bundle multiple questions in one message.

### 3. Apply the foundation

Generate files using the matching references. `.env` `DATABASE_URL` must match the chosen DB + dev mode (sqlite path, host Postgres URL, or `db` service host).

### 4. Boot check — mandatory before moving on

Run in the chosen mode:

- `migrate`
- `createsuperuser` (interactive — let the user enter credentials)
- `collectstatic --noinput` only if a static-files add-on was configured for local dev; skip for the bare foundation (`runserver` serves statics in DEBUG).

Do not proceed to add-ons until the user confirms they can log in to `/admin/`.

### 5. Add-ons, then production

Ask which add-ons the user wants. For production deployment, ask which target (VPS / managed / GitHub SSH) before loading the deploy reference.

### 6. README

After any setup step, update `README.md` with the key decisions (stack, DB, dev mode, add-ons, deploy target) and the main commands (install, test, migrate, run, deploy). Don't hardcode dependency versions — read them from `pyproject.toml` if you want to mention them.

### Don't improvise

Use the reference snippets as written.

- Env var names: always `DJANGO_DEBUG` / `DJANGO_SECRET_KEY` / `DJANGO_ALLOWED_HOSTS`. Never the unprefixed forms.
- Don't add packages the user didn't ask for (`django-extensions`, etc.).
- Don't create an app dir named after the project unless asked.
- Don't restate values in `local.py` / `production.py` that `base.py` already sets.
- Don't reimplement what `django-environ` already does (no manual `.split(",")`, no leftover `import os`).
