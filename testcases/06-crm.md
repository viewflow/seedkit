# 06 — django-silk + Django Tasks (DB backend) + GoatCounter + db-safety

Covers django-silk profiling, the Database backend for Django Tasks (no Redis), GoatCounter analytics, and the three db-safety tools: django-zeal (N+1 detection), django-migration-linter (CI audit), django-test-migrations (rollback tests).

## Prompt

```
/seedkit

Project name: 06-silk-lab
Purpose: profile a few request paths with django-silk and run a simple background email task on the DB backend.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: on the host (use `createdb silk_db`).
Lint with Ruff: yes.
Test runner: pytest (required for django-test-migrations).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: no.
Add-ons:
  - debug: django-silk (profiling + `@silk_profile`)
  - tasks: Django Tasks with the Database backend (`django-tasks-db`)
  - analytics: GoatCounter (self-hosted snippet, env-driven site code)
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Devcontainer: no.
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: yes.
  - Database safety tools: all three —
      - django-zeal: yes
      - django-migration-linter: yes
      - django-test-migrations: yes

Production setup: skip.

Run the foundation, the boot check, start `manage.py db_worker` in a second terminal, enqueue one example task and confirm it runs. Hit a profiled view and confirm the request appears under `/silk/`. Run `uv run manage.py lintmigrations`. Write a migration test in `jobs/tests/test_migrations.py` using the `migrator` fixture that applies the initial jobs migration forward and rolls it back. Run `uv run pytest`.
```

## Expected outcome

- `uv run manage.py runserver` boots; `/admin/` login works.
- `/silk/` renders and lists at least one captured request.
- `django-tasks` and `django-tasks-db` installed; `db_worker` consumes a queued task.
- GoatCounter snippet rendered in base template (site code from env).
- Ruff config present; `uv run ruff check .` exits 0.
- `django-extensions` installed as a **dev** dependency (`[tool.uv]` `dev-dependencies` or `[dependency-groups.dev]`), NOT a runtime dep. `django_extensions` appears in `INSTALLED_APPS` only via `local.py` (or DEBUG-gated for single-settings) — must NOT be in `base.py`'s static `INSTALLED_APPS` list. `uv run manage.py show_urls` runs without import error.
- `pages` app exposes `liveness` / `readiness`; `curl /healthz` → `ok`, `curl /readyz` → `ready`.
- `django-zeal`, `django-migration-linter`, `django-test-migrations` installed as **dev** deps only.
- `zeal` in `INSTALLED_APPS` only via `local.py` (not `base.py`); `ZEAL_RAISE_ON_VIOLATION = True` in local settings.
- `uv run manage.py lintmigrations` exits 0.
- `uv run pytest` passes, including the migration rollback test.

## Run

```sh
# Run from a scratch parent dir; the skill creates `06-silk-lab/`.
createdb silk_db || true
# AI executes the skill here, then:
cd 06-silk-lab
uv run manage.py runserver &
uv run manage.py db_worker &
# enqueue + observe one task; hit a profiled view; check /silk/
# django-extensions reachable
uv run manage.py show_urls > /dev/null
# Healthchecks
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# db-safety
uv run manage.py lintmigrations
uv run pytest
kill $(jobs -p) 2>/dev/null; pkill -f 'manage.py' 2>/dev/null; wait
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Read-only audit of this directory. Generated runtime artifacts (`.env`, local DB files, `__pycache__/`, `staticfiles/`) are expected. The starter has no business logic and no production hardening beyond what the prompt requested — out of scope. Report only issues that (i) prevent the scaffold from booting, (ii) make one of the smoke checks above fail, or (iii) are an outright security hole. Every claim must quote the file path and the literal substring you read; do not infer state from training-data priors. Skip nitpicks (docstrings, style, hypothetical scaling, 'consider adding X'). Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for — a starter scaffold is supposed to be small. If unsure whether something is a real bug right now, omit it. If you patched something during this run, list it under 'Fixes applied', not 'Bugs'. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; 'No issues found.' is a valid report." \
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
dropdb silk_db
```
