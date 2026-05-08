# 04 — Full docker-compose stack, S3 storage, Django-Tasks (RQ)

Covers full Compose dev mode, S3-compatible object storage, and the Django Tasks API with the Redis Queue backend.

## Prompt

```
/cookiecutter

Project name: 04-media-vault
Purpose: media-heavy app where uploads land in S3 and processing runs as Redis-queued background tasks.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (full stack: web + db + redis).
Lint with Ruff: yes.
Add-ons:
  - redis
  - storage: S3-compatible (use MinIO in local Compose; configure via env)
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`)
Production setup: skip.

Generate `docker-compose.yml` with services `web`, `db`, `redis`, `worker`, `minio`. Run the foundation, `docker compose up -d`, migrate, createsuperuser, and confirm a sample task enqueues and completes.
```

## Expected outcome

- `docker compose up -d` starts all five services healthy.
- `web` runs `runserver` on `:8000`; `/admin/` login works.
- `worker` runs `manage.py rqworker default` and processes a queued task.
- `minio` exposes a bucket; uploaded media land there (verify via `mc` or admin UI).
- `psycopg[binary]`, `django-tasks`, `django-tasks-rq`, `django-storages[s3]` (or `boto3`) in dependencies.
- Ruff config present; `docker compose exec web uv run ruff check .` exits 0.
- Named volumes for `pgdata`, `venv`, `uv-cache`, `minio-data`.

## Run

```sh
# Run from a scratch parent dir; the skill creates `04-media-vault/`.
# AI executes the skill here, then:
cd 04-media-vault
docker compose up -d
docker compose exec web uv run manage.py migrate
docker compose exec web uv run manage.py createsuperuser --noinput || true
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
# enqueue + observe one task
```

## Check report

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
