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

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
