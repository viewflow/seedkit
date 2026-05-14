# Managed deploy (Fly / Railway / Render)

Slim runtime image, no `uv` in the final stage. Secrets via the platform — `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`, `DATABASE_URL`, `REDIS_URL`, `SENTRY_DSN`, etc. — never hardcoded in `[env]`.

## fly.toml

```toml
app = "{project_slug}"
primary_region = "iad"

[build]

[env]
  PORT = "8000"
  DJANGO_SETTINGS_MODULE = "config.settings.production"
  DJANGO_BEHIND_PROXY = "True"  # trust X-Forwarded-Proto so SECURE_SSL_REDIRECT works behind Fly's proxy

[processes]
  web = "gunicorn config.wsgi -b 0.0.0.0:8000"
  worker = "celery -A config worker -l info"
  bolt = "python manage.py runbolt --host 0.0.0.0 --port 8000"

# Per-process settings override — bolt machine must NOT load admin/sessions/messages/staticfiles.
[[processes.env]]
  processes = ["bolt"]
  DJANGO_SETTINGS_MODULE = "config.settings.bolt"

[deploy]
  release_command = "python manage.py migrate --noinput"  # slim runtime has no uv

[http_service]
  internal_port = 8000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  processes = ["web"]

  [[http_service.checks]]
    path = "/readyz"  # /healthz is liveness; managed platforms want readiness
    interval = "15s"
    timeout = "2s"
```

Set secrets out-of-band:

```sh
fly secrets set DJANGO_SECRET_KEY=... DJANGO_ALLOWED_HOSTS=app.fly.dev DATABASE_URL=... REDIS_URL=...
```

## Dockerfile path convention

Multi-stage build, runtime stage has no `uv`. Place the venv at `/opt/venv` so `release_command` / `[processes]` can call `python` / `gunicorn` / `celery` directly:

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
RUN uv sync --frozen --no-dev --no-install-project

FROM python:3.12-slim-bookworm AS prod
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /app
COPY . .
EXPOSE 8000
CMD ["gunicorn", "config.wsgi", "-b", "0.0.0.0:8000"]
```

## mise.toml task

```toml
[tasks.deploy]
run = "fly deploy"
```
