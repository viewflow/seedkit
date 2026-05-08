# Celery

Django itself has no background-task system — the request/response cycle is the whole runtime. Celery is the long-established Python distributed task queue: workers process jobs off a broker (Redis here), with retries, rate limits, schedules (Beat), priority queues, chained workflows, and a large ecosystem (Flower UI, monitoring exporters). Use it when you have non-trivial background work — emails, image processing, periodic syncs, multi-step pipelines.

Requires Redis. Set up `reference/redis.md` first if not already done.

Ask the user if they also need **periodic tasks** (celery beat) — add the Beat section if yes.

## Install

```sh
uv add 'celery[redis]'
```

## config/celery.py

```python
import os
from celery import Celery

# Single-file layout: "config.settings"
# Split layout: "config.settings.production"
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

app = Celery("config")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
```

## config/\_\_init\_\_.py

```python
from .celery import app as celery_app

__all__ = ("celery_app",)
```

## Settings

Add to your settings module (`config/settings.py` for single-file, `config/settings/base.py` for split). If `redis.md` was already applied, reuse `REDIS_URL`; otherwise define it here:

```python
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379")

# Distinct logical DBs so cache.clear() doesn't wipe broker / result state.
CELERY_BROKER_URL = f"{REDIS_URL}/1"
CELERY_RESULT_BACKEND = f"{REDIS_URL}/2"
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True  # silence Celery 5+ deprecation
```

## Define a task

Tasks must live in a registered Django app (`<app>/tasks.py`) — `app.autodiscover_tasks()` only scans `INSTALLED_APPS`. **Don't put `tasks.py` in `config/`** — `config/` is the project package and isn't in `INSTALLED_APPS`, so tasks defined there are never discovered. If no domain app exists yet, create one (`uv run django-admin startapp <name>`) and put the task in `<name>/tasks.py`.

```python
# <app>/tasks.py
from celery import shared_task

@shared_task
def send_welcome_email(user_id: int) -> None:
    ...
```

## Enqueue

```python
send_welcome_email.delay(user.id)
```

## Local — docker-compose.yml

Mirror the dev `web` service: raw uv image + bind mount + shared `venv` / `uv-cache` volumes so code edits hit the worker without a rebuild.

```yaml
services:
  celery:
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
    command: sh -c "uv sync && uv run celery -A config worker -l info"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## VPS — docker-compose.prod.yml

Production image has `/app/.venv/bin` on `PATH`, so call `celery` directly — no `uv run` overhead per container start.

```yaml
services:
  celery:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: celery -A config worker -l info
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## Managed platforms

Run the worker as a separate process/service alongside web:

- **Fly.io** — add a `[processes]` section in `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "celery -A config worker -l info"
  ```
- **Railway / Render** — add a second service pointing at the same image with command `celery -A config worker -l info`.

---

## Periodic Tasks — Celery Beat

Add this section only if the user needs scheduled/periodic tasks.

Beat's default `PersistentScheduler` writes a `celerybeat-schedule` file (plus `-shm` and `-wal` SQLite sidecars) to the working directory at runtime. Add `celerybeat-schedule*` to `.gitignore` — the generic `*.sqlite3` rule misses them because they have no extension.

### Settings

Add to the same settings module as above:

```python
from celery.schedules import crontab

CELERY_BEAT_SCHEDULE = {
    "example-task": {
        "task": "{project_slug}.tasks.example_task",
        "schedule": crontab(hour=8, minute=0),  # daily at 08:00
    },
}
```

### Local — docker-compose.yml

```yaml
services:
  celery-beat:
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
    command: sh -c "uv sync && uv run celery -A config beat -l info"
    depends_on:
      - celery
```

### VPS — docker-compose.prod.yml

```yaml
services:
  celery-beat:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: celery -A config beat -l info
    env_file: .env.prod
    depends_on:
      - celery
```

### Managed platforms

Add a third process/service for beat alongside web and worker.
