# 03 — Postgres-in-Docker, Django on host, Celery + Beat

Covers the "Postgres in Docker, Django on host" hybrid mode, plus Redis-backed Celery with periodic tasks.

## Prompt

```
/cookiecutter

Project name: 03-jobs-board
Purpose: job board with background email notifications and a daily digest.

Settings layout: single file.
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: run only Postgres in Docker, Django runs on the host (publish 5432 to localhost).
Lint with Ruff: no.
Add-ons:
  - redis (for Celery)
  - tasks: Celery, with periodic tasks (Celery Beat)
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
```

## Check report

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
