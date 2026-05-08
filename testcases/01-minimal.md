# 01 — Minimal example

Smallest path that boots a working Django project. Baseline — if this fails, everything else is moot.

## Prompt

```
/cookiecutter

Project name: 01-minimal-blog
Purpose: a tiny blog to verify the skill works end-to-end.

Settings layout: single file (`config/settings.py`).
Database: SQLite.
Local dev mode: uv on host.
Lint with Ruff: no.
Custom user model: no.
Auth add-on: none (vanilla `django.contrib.auth`).
Add-ons: none.
Production setup: skip.

Run the foundation, the boot check (migrate + createsuperuser), and confirm /admin/ login works.
```

## Expected outcome

- `uv run manage.py runserver` boots without errors.
- `/admin/` renders and the superuser can log in.
- Files present: `pyproject.toml`, `uv.lock`, `manage.py`, `config/settings.py`, `db.sqlite3`, `.env`, `.gitignore`.
- No Docker, no Postgres deps, no Ruff config.

## Run

```sh
# Run from a scratch parent dir; the skill creates `01-minimal-blog/` via `uv init`.
# AI executes the skill here, then:
cd 01-minimal-blog
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
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

Leave the code in place; no external resources to remove (SQLite file lives inside the project dir).
