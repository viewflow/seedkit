# Django Tasks (Django 6.0+)

Django 6.0 ships the `django.tasks` API in core: a vendor-neutral `@task` decorator + `enqueue` / `enqueue_on_commit` / result-checking, modelled after `django.core.cache`. Pick a third-party backend for the actual queue. Lighter footprint than Celery (no separate broker required if you pick the DB backend), but no Beat-equivalent scheduler, no chained workflows, no Flower-class monitoring UI yet.

Ask the user which backend they prefer:
- **Database** (`django-tasks-db`) — simplest, no extra infrastructure, tasks stored in DB
- **Redis Queue** (`django-tasks-rq`) — needs Redis, better throughput for high volume

Ask if they also need **periodic tasks** (django-crontask) — add the crontask section if yes.

Settings snippets below assume your settings module is `config/settings.py` (single-file) or `config/settings/base.py` (split). Apply to whichever layout was chosen.

---

## Backend A: Database

### Install

```sh
uv add django-tasks-db
```

### INSTALLED_APPS

`django.tasks` is built into Django 6.0+, so it doesn't go in `INSTALLED_APPS`. Only the backend's app does:

```python
INSTALLED_APPS = [
    ...
    "django_tasks_db",   # ships migrations for the task table
]
```

### Settings

```python
TASKS = {
    "default": {
        "BACKEND": "django_tasks_db.DatabaseBackend",
    }
}
```

### Migrate

```sh
uv run manage.py migrate
```

### Run worker (host)

```sh
uv run manage.py db_worker
```

### Local — docker-compose.yml

Mirror the dev `web` service: raw uv image + bind mount + shared volumes so code edits reach the worker without a rebuild.

```yaml
services:
  worker:
    image: ghcr.io/astral-sh/uv:python3.12-bookworm-slim
    working_dir: /app
    environment:
      UV_CACHE_DIR: /tmp/uv-cache
      UV_LINK_MODE: copy
    volumes:
      - .:/app
      - venv:/app/.venv
      - uv-cache:/tmp/uv-cache
    env_file: .env
    command: sh -c "uv sync && uv run manage.py db_worker"
    depends_on:
      db:
        condition: service_healthy
```

### VPS — docker-compose.prod.yml

Production image has `/app/.venv/bin` on `PATH` — call `manage.py` directly via `python`.

```yaml
services:
  worker:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: python manage.py db_worker
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
```

---

## Backend B: Redis Queue

Requires Redis. Set up `reference/redis.md` first if not already done.

### Install

`django-rq` provides the `rqworker` management command + admin; `django-tasks-rq` is the adapter from `django.tasks` to RQ.

```sh
uv add django-tasks-rq django-rq
```

### INSTALLED_APPS

`django.tasks` is built in. `django_tasks_rq` is just a backend class. Only `django_rq` registers as an app:

```python
INSTALLED_APPS = [
    ...
    "django_rq",
]
```

### Settings

```python
TASKS = {
    "default": {
        "BACKEND": "django_tasks_rq.RQBackend",
        "QUEUES": ["default"],
    }
}

# django-rq reads RQ_QUEUES separately from TASKS. Use the URL form so
# host/port come from REDIS_URL (works in both Compose and host modes).
# Use a dedicated logical DB (/3) so it doesn't share with cache (/0)
# or Celery broker / results (/1, /2).
RQ_QUEUES = {
    "default": {"URL": f"{REDIS_URL}/3"},
}
```

### Run worker (host)

```sh
uv run manage.py rqworker default
```

### Local — docker-compose.yml

```yaml
services:
  worker:
    image: ghcr.io/astral-sh/uv:python3.12-bookworm-slim
    working_dir: /app
    environment:
      UV_CACHE_DIR: /tmp/uv-cache
      UV_LINK_MODE: copy
    volumes:
      - .:/app
      - venv:/app/.venv
      - uv-cache:/tmp/uv-cache
    env_file: .env
    command: sh -c "uv sync && uv run manage.py rqworker default"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

### VPS — docker-compose.prod.yml

```yaml
services:
  worker:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: python manage.py rqworker default
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

---

## Define and enqueue a task (both backends)

```python
from django.tasks import task

@task()
def send_welcome_email(user_id: int) -> None:
    ...
```

```python
from django.db import transaction

# Enqueue after the current transaction commits to avoid race conditions
transaction.on_commit(lambda: send_welcome_email.enqueue(user.id))
```

## Managed platforms

Run the worker as a separate process/service alongside web:

- **Fly.io** — add a `[processes]` section in `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "python manage.py db_worker"  # or rqworker default
  ```
- **Railway / Render** — add a second service pointing at the same image with the worker command.

---

## Periodic Tasks — django-crontask

Add this section only if the user needs scheduled/periodic tasks.

### Install

```sh
uv add django-crontask
```

### INSTALLED_APPS

```python
INSTALLED_APPS = [
    ...
    "crontask",
]
```

### Define a periodic task

```python
from django.tasks import task
from crontask import cron

@cron("0 8 * * *")  # daily at 08:00 (crontab syntax)
@task()
def daily_report() -> None:
    ...
```

### Run (host)

```sh
uv run manage.py crontask
```

### Local — docker-compose.yml

```yaml
services:
  cron:
    image: ghcr.io/astral-sh/uv:python3.12-bookworm-slim
    working_dir: /app
    environment:
      UV_CACHE_DIR: /tmp/uv-cache
      UV_LINK_MODE: copy
    volumes:
      - .:/app
      - venv:/app/.venv
      - uv-cache:/tmp/uv-cache
    env_file: .env
    command: sh -c "uv sync && uv run manage.py crontask"
    depends_on:
      db:
        condition: service_healthy
```

### VPS — docker-compose.prod.yml

```yaml
services:
  cron:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: python manage.py crontask
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
```

### Managed platforms

Add a third process/service for cron alongside web and worker.
