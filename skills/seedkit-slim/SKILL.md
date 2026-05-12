---
name: seedkit-slim
version: 26.20.2
description: Bootstrap a new Django project, or add components to an existing one — auth, payments, REST, Celery / django-tasks, async / WebSockets, Tailwind, S3, structlog, healthchecks, Docker, CI, deploy, dbbackup, Sentry. Slim variant — questionnaire only, no implementation guidance. Use whenever the user wants to scaffold Django or extend an existing Django project.
---

## How this skill works

Pure requirements-gathering. Ask the questions below, collect answers, then generate the project — you already know the packages, the settings, and the wiring.

Two paths:

- **New project** (empty dir): run §1 → §4.
- **Existing project** (`pyproject.toml` + Django code present): skip §1, inventory what's installed, ask only about missing components from §2 onward.

Before anything: `uv --version` to confirm uv is available. `none` (or `no`) is always a valid answer to any question.

**Use answers already given.** Scan the user's initial request before asking. Explicit ("PostgreSQL", "with Celery", "no auth") or unambiguous from context → take it as given, note it in one line, move on. Ask only what is missing.

Ask one question at a time. Never bundle.

## 1. Foundation — new projects only

1. Project name + one-line purpose.
2. Settings layout: `single settings.py` / `split base+local+production`.
3. Database: `sqlite` / `postgresql`.
4. Request handling: `wsgi` / `asgi` / `asgi+channels`. Default `wsgi`.
5. If postgresql: `host` / `docker` (single-service compose for local DB).
6. Custom `AUTH_USER_MODEL`: yes / no.

## 2. Add-ons

### 2.1 Developer Experience

1. Lint: `ruff` / none. Default none.
2. Tests: `pytest+pytest-django` / `manage.py test`. Default `manage.py test`.
3. Typecheck: `pyright+django-stubs` / none. Default none.
4. Pre-commit: yes / no. Default no.
5. Devcontainer: yes / no. Default no.
6. Debug toolbar: `django-orbit` / `django-silk` / none. Default none.
7. DB safety (multi-select): `django-zeal` / `django-migration-linter` / `django-test-migrations` / none. Default none. Skip `django-test-migrations` if pytest not chosen.
8. `django-extensions`: yes / no. Default no.
9. Logging: `structlog` / none. Default none.
10. Task runner: `mise` / `just` / `make` / `poe` / none. Default `mise`.

### 2.2 Auth & Accounts

1. Auth: `django-allauth` / `django-mail-auth` / none. Default none.
2. `django-axes`: yes / no. Default yes. Skip if auth=none.
3. 2FA: yes / no. Default no. Skip if auth=none. Use `django-allauth[mfa]` when auth=allauth, else `django-otp`.

### 2.3 Data & Storage

1. Cache: `sqlite` / `django-redis` / `locmem` / none. Default `sqlite` when DB=sqlite, else `locmem`.
2. Static + media: `whitenoise` / `django-storages[s3]` / none. Default none.

### 2.4 Background & Email

1. Background tasks: `celery` / `django-tasks` (db backend) / `django-tasks-rq` / none. Default `django-tasks` (db) when DB=sqlite, else none.
2. Email: `console` / `smtp` / `mailpit` / `django-anymail` / none. Always ask.

### 2.5 Frontend & Site Basics

1. Frontend: `tailwind` (standalone CLI) / none. Default none.
   - If tailwind: custom 404/403/500 templates — yes / no. Default no.
   - If tailwind: DaisyUI — yes / no. Always ask.
2. i18n (gettext, LocaleMiddleware): yes / no. Default no.
3. `django-cors-headers`: yes / no. Default no.
4. `robots.txt`: yes / no. Default no.

### 2.6 SaaS / Product

1. REST API: `django-modern-rest` / `django-bolt` / none. Default none.
2. Billing: `stripe` (raw SDK) / `dj-stripe` / none. Default none.
3. Analytics: `goatcounter` / `umami` / `shynet` / `ga4` / none. Default none.

### 2.7 Real-time

Only when Foundation §1.4 = `asgi+channels`.

1. Channel layer: `channels-redis` / `InMemoryChannelLayer`. Default `channels-redis`.

## 3. Production & Deploy

1. Security settings: yes / no. Default no.
   - If yes: `django-csp` — yes / no. Default yes.
2. Health checks (`/healthz`, `/readyz`): yes / no. Default yes.
3. Error reporting: `bugsink` / `sentry-sdk` / `glitchtip` / none. Default none.
4. GDPR helpers: yes / no. Default no.
5. CI on GitHub Actions: yes / no. Default no.
6. Deploy: `vps` (Docker + Caddy) / `managed` (Fly / Railway / Render) / `github-ssh` / none. Default none.
   - If `vps` or `github-ssh`: `django-dbbackup` — yes / no. Default yes.

## 4. Smoke + README

New projects only:

- Agent runs `migrate` and a `runserver` curl probe before piling on add-ons.
- After §3, ask the user to run `createsuperuser`, optionally `collectstatic`, then sign in at `/admin/`.
- Append decisions, stack summary, and key commands to `README.md`. Final line for new projects: `Built with [Seedkit](https://github.com/RobustaRush/seedkit).`
