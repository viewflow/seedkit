# Debug — django-orbit

Dashboard at `/orbit/`. Per-request event correlation via `family_hash`. Dev-only.

## Install

```sh
uv add --dev django-orbit
```

With MCP support (so AI assistants can query live telemetry):

```sh
uv add --dev "django-orbit[mcp]"
```

## Settings

In `config/settings.py` (or `config/settings/local.py` for split):

```python
if DEBUG:
    INSTALLED_APPS += ["orbit"]
    MIDDLEWARE = ["orbit.middleware.OrbitMiddleware"] + MIDDLEWARE

    ORBIT_CONFIG = {
        "IGNORE_PATHS": ["/orbit/", "/static/", "/media/"],
        "HIDE_REQUEST_HEADERS": ["Authorization", "Cookie", "X-API-Key"],
        "HIDE_REQUEST_BODY_KEYS": ["password", "token", "api_key", "secret"],
        "SLOW_QUERY_THRESHOLD_MS": 100,
    }
```

`OrbitMiddleware` must be first.

## URLs

```python
from django.conf import settings

if settings.DEBUG:
    from django.urls import include, path
    urlpatterns += [path("orbit/", include("orbit.urls"))]
```

## Migrate

```sh
uv run manage.py migrate
```

## Logging (optional)

`django-orbit` is a dev dep, so this `LOGGING` block lives in `config/settings/local.py` only — never `base.py` or `production.py`. Keep a `console` handler alongside `orbit` so `runserver` output isn't swallowed:

```python
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "console": {"class": "logging.StreamHandler"},
        "orbit": {"()": "orbit.handlers.OrbitLogHandler"},
    },
    "root": {"handlers": ["console", "orbit"], "level": "DEBUG"},
}
```

Single-file layout: gate on `if DEBUG:`.

## MCP — AI assistant integration (optional)

`claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`):

```json
{
  "mcpServers": {
    "django-orbit": {
      "command": "python",
      "args": ["manage.py", "orbit_mcp"],
      "cwd": "/path/to/project",
      "env": {"DJANGO_SETTINGS_MODULE": "config.settings"}
    }
  }
}
```

Tools: recent requests, slow queries, exceptions, N+1 patterns, keyword search, performance stats.

## Dashboard

- `http://localhost:8000/orbit/` — live event feed.
- `http://localhost:8000/orbit/stats/` — Apdex, P50–P99, error rate, cache hit rate.
