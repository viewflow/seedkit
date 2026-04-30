# Debug

Two options — ask the user which one they want before proceeding:

- **Orbit** — observability dashboard: requests, SQL, logs, exceptions, cache, ORM events, emails, background jobs, Redis, outgoing HTTP. Works with APIs and SPAs (no template injection). Choose this for general debugging and observability.
- **Silk** — profiling dashboard: request/response profiling + `@silk_profile` decorator for profiling specific Python functions. Choose this when you need to pinpoint CPU time inside specific code paths.

---

## Option A: django-orbit

Dashboard at `/orbit/`. All events correlated per request via `family_hash`.

### Install

```sh
uv add --dev django-orbit
```

With MCP support (lets AI assistants query live telemetry):

```sh
uv add --dev "django-orbit[mcp]"
```

### Settings

In `config/settings.py` (or `config/settings/local.py` for split settings):

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

`OrbitMiddleware` must be first to capture the full request before other middleware runs.

### URLs

```python
from django.conf import settings

if settings.DEBUG:
    from django.urls import include, path
    urlpatterns += [path("orbit/", include("orbit.urls"))]
```

### Migrate

```sh
uv run manage.py migrate
```

### Logging (optional)

```python
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "orbit": {"()": "orbit.handlers.OrbitLogHandler"},
    },
    "root": {"handlers": ["orbit"], "level": "DEBUG"},
}
```

### MCP — AI assistant integration (optional)

Add to `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`):

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

Available tools: recent requests, slow queries, exceptions, N+1 patterns, keyword search, performance stats.

### Dashboard

`http://localhost:8000/orbit/` — live event feed  
`http://localhost:8000/orbit/stats/` — Apdex, P50–P99, error rate, cache hit rate

---

## Option B: django-silk

Profiling dashboard at `/silk/`. Stores request/response and SQL data in the database. Unique feature: `@silk_profile` decorator for profiling specific Python functions.

### Install

```sh
uv add --dev django-silk
```

### Settings

```python
if DEBUG:
    INSTALLED_APPS += ["silk"]
    MIDDLEWARE = ["silk.middleware.SilkyMiddleware"] + MIDDLEWARE
```

### URLs

```python
if settings.DEBUG:
    from django.urls import include, path
    urlpatterns += [path("silk/", include("silk.urls", namespace="silk"))]
```

### Migrate

```sh
uv run manage.py migrate
```

### Function profiling (optional)

```python
from silk.profiling.profiler import silk_profile

@silk_profile(name="my expensive operation")
def expensive_operation():
    ...

# or as a context manager
with silk_profile(name="inner block"):
    ...
```

### Clear old data

Silk accumulates data indefinitely — clear it periodically:

```sh
uv run manage.py silk_clear_request_log
```

Or configure automatic clearing in settings:

```python
SILKY_MAX_RECORDED_REQUESTS = 1000
SILKY_MAX_RECORDED_REQUESTS_CHECK_PERCENT = 10
```

### Dashboard

`http://localhost:8000/silk/`
