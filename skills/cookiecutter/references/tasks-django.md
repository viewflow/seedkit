# Django Tasks (Django 6.0+)

Uses the built-in `django.tasks` API. Requires a third-party backend for production.

Ask the user which backend they prefer:
- **Database** (`django-tasks-db`) — simplest, no extra infrastructure, tasks stored in DB
- **Redis Queue** (`django-tasks-rq`) — needs Redis, better throughput for high volume

Ask if they also need **periodic tasks** (django-crontask) — add the crontask section if yes.

---

## Backend A: Database

### Install

```sh
uv add django-tasks-db
```

### INSTALLED_APPS

```python
INSTALLED_APPS = [
    ...
    "django_tasks",
    "django_tasks_db",
]
```

### config/settings/base.py

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

### Run worker

```sh
uv run manage.py db_worker
```

### Local — docker-compose.yml

```yaml
services:
  worker:
    build: .
    command: uv run manage.py db_worker
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
```

### VPS — docker-compose.prod.yml

```yaml
services:
  worker:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: uv run manage.py db_worker
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
```

---

## Backend B: Redis Queue

Requires Redis. Set up `reference/redis.md` first if not already done.

### Install

```sh
uv add django-tasks-rq
```

### INSTALLED_APPS

```python
INSTALLED_APPS = [
    ...
    "django_tasks",
    "django_tasks_rq",
]
```

### config/settings/base.py

```python
TASKS = {
    "default": {
        "BACKEND": "django_tasks_rq.RQBackend",
        "QUEUES": ["default"],
    }
}
```

### Run worker

```sh
uv run manage.py rqworker default
```

### Local — docker-compose.yml

```yaml
services:
  worker:
    build: .
    command: uv run manage.py rqworker default
    env_file: .env
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
    command: uv run manage.py rqworker default
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

Run the worker as a separate process/service alongside the web process:

- **Fly.io**: add a `[processes]` section in `fly.toml`:
  ```toml
  [processes]
    web = "uv run gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "uv run manage.py db_worker"  # or rqworker default
  ```
- **Railway / Render**: add a second service pointing at the same Docker image with the worker command.

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

### Run

```sh
uv run manage.py crontask
```

### Local — docker-compose.yml

```yaml
services:
  cron:
    build: .
    command: uv run manage.py crontask
    env_file: .env
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
    command: uv run manage.py crontask
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy
```

### Managed platforms

Add a third process/service for cron alongside web and worker.
