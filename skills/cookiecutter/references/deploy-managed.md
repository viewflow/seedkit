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
  release_command = "uv run manage.py migrate"

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

Same pattern: point at `Dockerfile`, set env vars in dashboard, configure release command to `uv run manage.py migrate`.
