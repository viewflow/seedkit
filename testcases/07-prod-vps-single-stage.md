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
Lint with Ruff: yes.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login + mandatory verification).
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Add-ons:
  - redis
  - tasks: Celery (no Beat)
  - storage: WhiteNoise (static), media volume on the VPS host
  - email: SMTP in production, console backend in local. Use a placeholder Postmark URL (`EMAIL_URL=smtp+tls://<token>:<token>@smtp.postmarkapp.com:587`); also wire `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`, `DJANGO_ADMINS`.
Production setup:
  - apply Django security settings (HSTS, secure cookies, X-Frame, SSL redirect)
  - error reporting: Sentry SaaS (sentry-sdk)
  - CI: GitHub Actions test workflow
  - deploy target: VPS (Docker + Caddy)
  - production Dockerfile: single-stage
Skip GDPR for this case.

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `Caddyfile`, `.github/workflows/test.yml`. Do not actually push to a remote VPS — just verify all artifacts are present and `docker build .` succeeds.
```

## Expected outcome

- Local `docker compose up -d` starts web + db + redis + worker, `/admin/` login works.
- Production Dockerfile is single-stage, uses `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, two-step `uv sync`, `/app/.venv/bin` on `PATH`, runs as `django` user.
- `docker build .` succeeds; final image is non-root and has `gunicorn` on PATH.
- `Caddyfile` terminates TLS, proxies `:8000`, serves `/static/` and `/media/`.
- `docker-compose.prod.yml` has `web`, `db`, `redis`, `celery` services with `restart: unless-stopped`.
- Sentry initialised in `production.py` only, DSN from env.
- `.github/workflows/test.yml` runs migrations + pytest against Postgres.
- Security settings apply only in `production.py`.
- `users/` app with `AbstractUser` subclass and admin registration; `AUTH_USER_MODEL = "users.User"` set **before** the initial migration; `users_user` table exists.
- `django-allauth` installed; `allauth`, `allauth.account`, `django.contrib.sites` in `INSTALLED_APPS`; `AccountMiddleware` in `MIDDLEWARE`; `accounts/` URL include; `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`; `/accounts/login/` and `/accounts/signup/` render.
- `structlog` installed; `LOGGING` with `json` (prod) / `console` (dev) formatters; `RequestContextMiddleware` inserted into `MIDDLEWARE`; production logs are valid JSON lines carrying `request_id`.

## Run

```sh
# Run from a scratch parent dir; the skill creates `07-vps-saas/`.
# AI executes the skill here, then:
cd 07-vps-saas
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
docker build -t 07-vps-saas:test .
```

## Log check

Run after the boot check; the testcase is a failure if any of these print matches:

```sh
docker compose logs --tail=80 web db redis celery
! docker compose logs web celery 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
# celery should report worker ready:
docker compose logs celery 2>&1 | grep -iE 'celery@.*ready|mingle|sync with'
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

Leave the code. Tear down local containers and remove the built image. No remote VPS was provisioned — nothing to undo there.

```sh
docker compose down -v
docker rmi 07-vps-saas:test
```
