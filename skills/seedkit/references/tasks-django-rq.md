# Django Tasks — Redis Queue backend

Docs: <https://github.com/RealOrangeOne/django-tasks-rq> · <https://python-rq.org/>

Requires Redis (`references/redis.md`).

`django-rq` provides the `rqworker` management command + admin. `django.tasks` (built into Django 6.0+) is the Tasks API — `from django.tasks import task`. `django-tasks-rq` is the adapter from that API to RQ.

## Install

```sh
uv add django-tasks django-tasks-rq django-rq
```

`django-tasks` ships `django.tasks` for Django <6.0 and is a transitive dep of `django-tasks-rq` — declare it explicitly so the dependency isn't implicit.

## INSTALLED_APPS

`django_rq` and `django_tasks_rq` are both apps and both register:

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
# broker / results (/1, /2).
RQ_QUEUES = {
    "default": {"URL": f"{REDIS_URL}/3"},
}

# Job class for the rqworker. Goes in the top-level RQ dict (NOT inside
# RQ_QUEUES[queue]) — django-rq's get_job_class() reads from settings.RQ
# only. Without this the worker fetches jobs as rq.job.Job (the upstream
# default) and every task explodes with `'Task' object is not callable`
# because django-tasks-rq's overridden _execute() never runs.
RQ = {"JOB_CLASS": "django_tasks_rq.Job"}
```

## Run worker (host)

```sh
uv run manage.py rqworker default
```

`settings.RQ["JOB_CLASS"]` is read globally by `rqworker`. No `--job-class` flag needed.

## Local — docker-compose.yml

```yaml
services:
  worker:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app
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
