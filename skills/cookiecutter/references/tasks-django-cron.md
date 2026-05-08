# Django Tasks — Periodic (django-crontask)

Add this only if the user needs scheduled tasks. Works alongside either Database or Redis Queue backend.

## Install

```sh
uv add django-crontask
```

## INSTALLED_APPS

```python
INSTALLED_APPS = [
    ...
    "crontask",
]
```

## Define

```python
from django.tasks import task
from crontask import cron

@cron("0 8 * * *")  # daily at 08:00 (crontab syntax)
@task()
def daily_report() -> None:
    ...
```

## Run (host)

```sh
uv run manage.py crontask
```

## Local — docker-compose.yml

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

## VPS — docker-compose.prod.yml

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

## Managed platforms

Add a third process for cron alongside web and worker.
