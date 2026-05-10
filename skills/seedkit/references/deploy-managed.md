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
  DJANGO_BEHIND_PROXY = "True"        # Fly's edge terminates TLS

# Required prod settings come from `fly secrets set` (below) — do NOT
# hardcode here:
#   DJANGO_SECRET_KEY        — generate with secrets.token_urlsafe
#   DJANGO_ALLOWED_HOSTS     — your fly.dev hostname + custom domain.
#                              Without it ALLOWED_HOSTS=[] and DEBUG=False
#                              return 400 for every request.
#   DJANGO_CSRF_TRUSTED_ORIGINS — https://<host> for each allowed host
#   DATABASE_URL             — auto-set by `fly postgres attach`
#   EMAIL_URL                — see references/email.md
#   SENTRY_DSN               — if error-reporting wired

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
fly secrets set \
    DJANGO_SECRET_KEY=$(python -c 'import secrets; print(secrets.token_urlsafe(50))') \
    DJANGO_ALLOWED_HOSTS=$(fly status -j | jq -r '.Hostname'),example.com \
    DJANGO_CSRF_TRUSTED_ORIGINS=https://example.com \
    EMAIL_URL=consolemail://     # replace with real provider URL
fly deploy
```

## Railway / Render

Same pattern: point at `Dockerfile`, set env vars in dashboard, configure release command to `python manage.py migrate` (not `uv run` — the multi-stage runtime image only ships the venv).
