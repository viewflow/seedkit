# django-silk

Request/SQL profiler. Dev-only — exposing it in prod leaks per-request internals and adds heavy overhead.

## Install

```sh
uv add --group dev django-silk
```

## Settings — gate on DEBUG

```python
# config/settings.py (or split: in local.py only — never in base.py)
if DEBUG:
    INSTALLED_APPS += ["silk"]
    MIDDLEWARE += ["silk.middleware.SilkyMiddleware"]
```

## URLs — gate the mount

```python
# config/urls.py
from django.conf import settings

if settings.DEBUG:
    urlpatterns += [path("silk/", include("silk.urls", namespace="silk"))]
```
