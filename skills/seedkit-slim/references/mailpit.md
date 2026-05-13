# Mailpit

Dev SMTP catcher. One-service compose; uv-on-host hits the published port.

## docker-compose.yml

```yaml
services:
  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "127.0.0.1:1025:1025"  # SMTP — bind to loopback, not 0.0.0.0
      - "127.0.0.1:8025:8025"  # UI
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8025/"]
      interval: 5s
      retries: 12
```

Bring it up with `docker compose up -d --wait --wait-timeout 60` — bare `--wait` exits immediately on older Compose.

## Settings via EMAIL_URL

```python
# config/settings.py
EMAIL_CONFIG = env.email_url("EMAIL_URL", default="consolemail://")
vars().update(EMAIL_CONFIG)
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", default="webmaster@localhost")
SERVER_EMAIL = env("SERVER_EMAIL", default=DEFAULT_FROM_EMAIL)
```

## .env

```sh
EMAIL_URL=smtp://localhost:1025  # uv-on-host hits the published port, not the docker service hostname
DEFAULT_FROM_EMAIL=dev@example.com
```
