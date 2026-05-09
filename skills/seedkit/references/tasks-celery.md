# Celery

Django has no background-task system. Celery is the established Python distributed queue: workers process jobs off a broker (Redis here), with retries, rate limits, schedules (Beat), priority queues, chained workflows. Use it for non-trivial background work — emails, image processing, periodic syncs.

Requires Redis (`references/redis.md`).

Ask the user about **periodic tasks** (Beat) — apply that section if yes.

## Install

```sh
uv add 'celery[redis]'
```

## config/celery.py

```python
import os
from celery import Celery

# Single-file: "config.settings". Split: "config.settings.production".
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

In `config/settings.py` (or `config/settings/base.py`). If `redis.md` set `REDIS_URL`, reuse it.

```python
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379")

CELERY_BROKER_URL = f"{REDIS_URL}/1"
CELERY_RESULT_BACKEND = f"{REDIS_URL}/2"
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True  # silence Celery 5+ deprecation
```

## Define a task

Tasks must live in a registered Django app — `app.autodiscover_tasks()` only scans `INSTALLED_APPS`. **Not in `config/`** (it isn't in `INSTALLED_APPS`). If no domain app exists, `uv run django-admin startapp <name>` first.

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

Reuse the dev image (`Dockerfile.dev` from `references/docker.md`) so the worker shares the bind-mounted source for live reload:

```yaml
services:
  celery:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app
      - /app/.venv          # anonymous volume — same shadowing trick as web
    env_file: .env
    command: celery -A config worker -l info
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## VPS — docker-compose.prod.yml

Production image has `/app/.venv/bin` on `PATH` — call `celery` directly:

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

- **Fly.io** — `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "celery -A config worker -l info"
  ```
- **Railway / Render** — second service on the same image with command `celery -A config worker -l info`.

---

## Periodic tasks — Celery Beat

Beat's default `PersistentScheduler` writes `celerybeat-schedule` (+ `-shm`, `-wal` SQLite sidecars) at runtime. Add `celerybeat-schedule*` to `.gitignore` — the `*.sqlite3` rule misses them (no extension).

### Settings

```python
from celery.schedules import crontab

CELERY_BEAT_SCHEDULE = {
    "example-task": {
        "task": "{project_slug}.tasks.example_task",
        "schedule": crontab(hour=8, minute=0),
    },
}
```

### Local — docker-compose.yml

```yaml
services:
  celery-beat:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app
      - /app/.venv
    env_file: .env
    command: celery -A config beat -l info
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

Add a third process for beat alongside web and worker.
