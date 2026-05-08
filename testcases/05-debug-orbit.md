# 05 — django-orbit debug dashboard + Mailpit

Covers the django-orbit observability dashboard (with MCP) and the Mailpit dev mail catcher.

## Prompt

```
/cookiecutter

Project name: 05-orbit-demo
Purpose: scratch project to exercise django-orbit and verify outbound mail flows are captured.

Settings layout: single file.
Database: SQLite.
Local dev mode: uv on host.
Lint with Ruff: yes.
Custom user model: no.
Auth add-on: none.
Add-ons:
  - debug: django-orbit (observability dashboard + MCP)
  - email: console backend in local, plus Mailpit running in Docker for richer inspection
Run the foundation + boot check. Spin up Mailpit via a one-service `docker-compose.yml`, point Django at SMTP `localhost:1025`, send a test mail, and confirm it appears in Mailpit's UI on `:8025`.
```

## Expected outcome

- `uv run manage.py runserver` boots; `/admin/` login works.
- `django-orbit` installed and visible at its mounted URL; MCP endpoint responds.
- `docker compose up -d mailpit` runs; sending a mail through `EmailMessage(...).send()` shows up in Mailpit UI.
- Ruff config present; `uv run ruff check .` exits 0.

## Run

```sh
# Run from a scratch parent dir; the skill creates `05-orbit-demo/`.
# AI executes the skill here, then:
cd 05-orbit-demo
docker compose up -d mailpit
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf http://127.0.0.1:8025/ > /dev/null
# send a test mail via shell, check Mailpit JSON API for receipt
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

Leave the code. Tear down the Mailpit container:

```sh
docker compose down -v
```
