# django-orbit

Observability dashboard + MCP. App label `orbit`. Mount only when `DEBUG`.

## Install

```sh
uv add --group dev 'django-orbit[mcp]'
```

## Settings — gate everything on DEBUG

```python
# config/settings.py
if DEBUG:
    INSTALLED_APPS += ["orbit"]
    # Insert after SecurityMiddleware so orbit sees the rest of the chain.
    MIDDLEWARE.insert(1, "orbit.middleware.OrbitMiddleware")
```

Orbit ships its own migrations — `migrate` picks them up. Exposing it without the `DEBUG` gate leaks request/SQL/cache internals.

## URLs — gate the mount

```python
# config/urls.py
from django.conf import settings

if settings.DEBUG:
    urlpatterns += [path("orbit/", include("orbit.urls"))]
```

## Logging — append handler inside the same DEBUG block

`LOGGING` stays at module scope; only the orbit handler is debug-only:

```python
if DEBUG:
    LOGGING["handlers"]["orbit"] = {"class": "orbit.handlers.OrbitLogHandler"}
    LOGGING["root"]["handlers"].append("orbit")
```
