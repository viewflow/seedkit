# Django Tasks — Redis Queue backend

Requires Redis (`references/redis.md`).

`django-rq` provides the `rqworker` management command + admin. `django-tasks-rq` is the adapter from `django.tasks` to RQ.

## Install

```sh
uv add django-tasks-rq django-rq
```

## INSTALLED_APPS

`django.tasks` is built in. `django_rq` and `django_tasks_rq` are both apps and both register:

```python
INSTALLED_APPS = [
    ...
    "django_rq",
    "django_tasks_rq",
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
# broker / results (/1, /2). JOB_CLASS lifts the django-tasks-rq Job into
# every queue so workers don't need a --job-class flag.
RQ_QUEUES = {
    "default": {
        "URL": f"{REDIS_URL}/3",
        "JOB_CLASS": "django_tasks_rq.Job",
    },
}
```

## Run worker (host)

```sh
uv run manage.py rqworker default
```

The `JOB_CLASS` in `RQ_QUEUES` is enough — `rqworker` reads it per queue. No `--job-class` flag needed.

## Local — docker-compose.yml

```yaml
services:
  worker:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app
      - /app/.venv
    env_file: .env
    command: python manage.py rqworker default
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
