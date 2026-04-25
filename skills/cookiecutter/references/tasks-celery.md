# Celery

Requires Redis. Set up `reference/redis.md` first if not already done.

Ask the user if they also need **periodic tasks** (celery beat) — add the Beat section if yes.

## Install

```sh
uv add celery[redis]
```

## config/celery.py

```python
import os
from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.production")

app = Celery("config")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
```

## config/\_\_init\_\_.py

```python
from .celery import app as celery_app

__all__ = ("celery_app",)
```

## config/settings/base.py

Add after `REDIS_URL` (or define it here if Redis reference wasn't used):

```python
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379/0")

CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
```

## Define a task

```python
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

Add `celery` service (shares the same image as `web`):

```yaml
services:
  celery:
    build: .
    command: uv run celery -A config worker -l info
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## VPS — docker-compose.prod.yml

```yaml
services:
  celery:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: uv run celery -A config worker -l info
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## Managed platforms

Run the worker as a separate process/service alongside the web process:

- **Fly.io**: add a `[processes]` section in `fly.toml`:
  ```toml
  [processes]
    web = "uv run gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "uv run celery -A config worker -l info"
  ```
- **Railway / Render**: add a second service pointing at the same Docker image with command `uv run celery -A config worker -l info`.

---

## Periodic Tasks — Celery Beat

Add this section only if the user needs scheduled/periodic tasks.

### config/settings/base.py

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
    build: .
    command: uv run celery -A config beat -l info
    env_file: .env
    depends_on:
      - celery
```

### VPS — docker-compose.prod.yml

```yaml
services:
  celery-beat:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: uv run celery -A config beat -l info
    env_file: .env.prod
    depends_on:
      - celery
```

### Managed platforms

Add a third process/service for beat alongside web and worker.
