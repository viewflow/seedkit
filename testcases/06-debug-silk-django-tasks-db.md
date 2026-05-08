# 06 — django-silk + Django Tasks (DB backend) + GoatCounter

Covers django-silk profiling, the Database backend for Django Tasks (no Redis), and GoatCounter analytics.

## Prompt

```
/cookiecutter

Project name: 06-silk-lab
Purpose: profile a few request paths with django-silk and run a simple background email task on the DB backend.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: on the host (use `createdb silk_db`).
Lint with Ruff: yes.
Add-ons:
  - debug: django-silk (profiling + `@silk_profile`)
  - tasks: Django Tasks with the Database backend (`django-tasks-db`)
  - analytics: GoatCounter (self-hosted snippet, env-driven site code)
Production setup: skip.

Run the foundation, the boot check, start `manage.py db_worker` in a second terminal, enqueue one example task and confirm it runs. Hit a profiled view and confirm the request appears under `/silk/`.
```

## Expected outcome

- `uv run manage.py runserver` boots; `/admin/` login works.
- `/silk/` renders and lists at least one captured request.
- `django-tasks` and `django-tasks-db` installed; `db_worker` consumes a queued task.
- GoatCounter snippet rendered in base template (site code from env).
- Ruff config present; `uv run ruff check .` exits 0.

## Run

```sh
# Run from a scratch parent dir; the skill creates `06-silk-lab/`.
createdb silk_db || true
# AI executes the skill here, then:
cd 06-silk-lab
uv run manage.py runserver &
uv run manage.py db_worker &
# enqueue + observe one task; hit a profiled view; check /silk/
```

## Check report

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
