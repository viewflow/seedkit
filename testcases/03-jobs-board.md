# 03 — Postgres-in-Docker, Django on host, Celery + Beat

Covers the "Postgres in Docker, Django on host" hybrid mode, plus Redis-backed Celery with periodic tasks.

## Prompt

```
/seedkit

Project name: 03-jobs-board
Purpose: job board with background email notifications and a daily digest.

Settings layout: single file.
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: run only Postgres in Docker, Django runs on the host (publish 5432 to localhost).
Lint with Ruff: no.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): yes.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Add-ons:
  - redis (for Celery)
  - tasks: Celery, with periodic tasks (Celery Beat)
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.

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
kill $(jobs -p) 2>/dev/null; pkill -f 'manage.py' 2>/dev/null; pkill -f 'celery' 2>/dev/null; wait
```

## Log check

Run after the boot check; the testcase is a failure if any of these print matches:

```sh
docker compose logs --tail=50 db redis
# fail if anything in db/redis logs looks fatal:
! docker compose logs db redis 2>&1 | grep -iE 'fatal|panic|traceback'
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

Leave the code. Tear down containers and volumes:

```sh
docker compose down -v
```
