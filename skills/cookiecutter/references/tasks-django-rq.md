# Django Tasks — Redis Queue backend

Requires Redis (`references/redis.md`).

`django-rq` provides the `rqworker` management command + admin. `django-tasks-rq` is the adapter from `django.tasks` to RQ.

## Install

```sh
uv add django-tasks-rq django-rq
```

## INSTALLED_APPS

`django.tasks` is built in. `django_tasks_rq` is just a backend class. Only `django_rq` registers as an app:

```python
INSTALLED_APPS = [
    ...
    "django_rq",
]
```

## Settings

```python
TASKS = {
    "default": {
        "BACKEND": "django_tasks_rq.RQBackend",
        "QUEUES": ["default"],
    }
}

# django-rq reads RQ_QUEUES separately from TASKS. URL form so host/port
# come from REDIS_URL. /3 keeps it isolated from cache (/0) and Celery
# broker / results (/1, /2).
RQ_QUEUES = {
    "default": {"URL": f"{REDIS_URL}/3"},
}
```

## Run worker (host)

```sh
uv run manage.py rqworker default
```

## Local — docker-compose.yml

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

## VPS — docker-compose.prod.yml

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

## Managed platforms

- **Fly.io** — `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "python manage.py rqworker default"
  ```
- **Railway / Render** — second service on the same image, command `python manage.py rqworker default`.
