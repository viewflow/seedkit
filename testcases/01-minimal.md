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

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
