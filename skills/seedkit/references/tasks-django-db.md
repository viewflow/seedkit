# Django Tasks — Database backend

Docs: <https://github.com/RealOrangeOne/django-tasks-database>

`django-tasks-db` stores tasks in your existing DB. No broker, no extra service.

## Install

```sh
uv add django-tasks-db
```

## INSTALLED_APPS

`django.tasks` is built into Django 6.0+. Only the backend's app registers:

```python
INSTALLED_APPS = [
    ...
    "django_tasks_db",   # ships migrations for the task table
]
```

## Settings

```python
TASKS = {"default": {"BACKEND": "django_tasks_db.DatabaseBackend"}}
```

## Migrate

```sh
uv run manage.py migrate
```

## Run worker (host)

```sh
uv run manage.py db_worker
```

## Local — docker-compose.yml

Mirror the dev `web` service so code edits reach the worker:

```yaml
services:
  worker:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app
    env_file: .env
    command: python manage.py db_worker
    depends_on:
      db:
        condition: service_healthy
```

## VPS — docker-compose.prod.yml

Production image has `/opt/venv/bin` on `PATH`:

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

## Managed platforms

- **Fly.io** — `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "python manage.py db_worker"
  ```
- **Railway / Render** — second service on the same image, command `python manage.py db_worker`.
