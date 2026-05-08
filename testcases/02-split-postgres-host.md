# 02 — Split settings, Postgres on host, WhiteNoise + SMTP

Covers split settings layout, host Postgres, Ruff, WhiteNoise statics, and SMTP email.

## Prompt

```
/cookiecutter

Project name: 02-shop
Purpose: small e-commerce site with admin and SMTP transactional email.

Settings layout: split (`config/settings/base.py`, `local.py`, `production.py`).
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: on the host (use `createdb` for the project DB).
Lint with Ruff: yes.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login, mandatory email verification, no social providers).
Add-ons:
  - storage: WhiteNoise for static files (no media volume yet)
  - email: SMTP (console backend in local, SMTP in production)
Production setup: skip.

Assume Postgres is already running locally on port 5432 with user `postgres` / password `postgres`. Create database `shop_db` if missing (Postgres identifiers can't start with a digit, so use a clean name). Run the foundation + boot check.
```

## Expected outcome

- `uv run manage.py runserver` boots; `/admin/` login works.
- `psycopg[binary]` in dependencies; `DATABASE_URL=postgres://...@localhost:5432/shop_db` in `.env`.
- `config/settings/{base,local,production}.py` present; `manage.py` points at `config.settings.local`, `wsgi.py` at `config.settings.production`.
- Ruff config in `pyproject.toml`; `uv run ruff check .` exits 0.
- WhiteNoise middleware listed in production settings only.
- Email backend `django.core.mail.backends.console.EmailBackend` in local; SMTP wired via env in production.
- `users/` app with `AbstractUser` subclass and admin registration; `AUTH_USER_MODEL = "users.User"` set **before** the initial migration; `users_user` table exists (no `auth_user`).
- `django-allauth` installed; `allauth`, `allauth.account`, `django.contrib.sites` in `INSTALLED_APPS`; `AccountMiddleware` in `MIDDLEWARE`; `accounts/` URL include; `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`; `/accounts/login/` and `/accounts/signup/` render.

## Run

```sh
# Run from a scratch parent dir; the skill creates `02-shop/` via `uv init`.
createdb shop_db || true
# AI executes the skill here, then:
cd 02-shop
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
uv run ruff check .
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Audit the existing code in this directory. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content, AND no production hardening (no security settings, error reporting, GDPR, CI, deploy config, or production Dockerfile). Focus on configuration correctness for the dev/foundation scope and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, domain models, or production-only settings — those are out of scope for this case. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially cookiecutter). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code. Drop the host Postgres database:

```sh
dropdb shop_db
```
