# Deploy — Managed (Fly.io / Railway / Render)

## Fly.io

### fly.toml

```toml
app = "{project_slug}"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[env]
  PORT = "8000"

[deploy]
  # `python` not `uv run`: the multi-stage Dockerfile's runtime stage
  # (python:3.X-slim-bookworm) has no uv binary — only the venv. /app/.venv/bin
  # is on PATH per the Dockerfile so `python` resolves there.
  release_command = "python manage.py migrate"

[[services]]
  internal_port = 8000
  protocol = "tcp"

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
```

### Commands

```sh
fly launch --no-deploy
fly postgres create
fly postgres attach <db-name>
fly secrets set DJANGO_SECRET_KEY=... DJANGO_ALLOWED_HOSTS=...
fly deploy
```

## Railway / Render

Same pattern: point at `Dockerfile`, set env vars in dashboard, configure release command to `python manage.py migrate` (not `uv run` — the multi-stage runtime image only ships the venv).
