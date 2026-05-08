# Debug — django-silk

Profiling dashboard at `/silk/`. Stores request / response and SQL data in the database. Unique feature: `@silk_profile` for profiling specific Python functions. Dev-only.

## Install

```sh
uv add --dev django-silk
```

## Settings

```python
if DEBUG:
    INSTALLED_APPS += ["silk"]
    MIDDLEWARE = ["silk.middleware.SilkyMiddleware"] + MIDDLEWARE
```

## URLs

```python
if settings.DEBUG:
    from django.urls import include, path
    urlpatterns += [path("silk/", include("silk.urls", namespace="silk"))]
```

## Migrate

```sh
uv run manage.py migrate
```

## Function profiling

```python
from silk.profiling.profiler import silk_profile

@silk_profile(name="my expensive operation")
def expensive_operation():
    ...

with silk_profile(name="inner block"):
    ...
```

## Clear old data

Silk accumulates indefinitely. Clear manually:

```sh
uv run manage.py silk_clear_request_log
```

Or auto-cap in settings:

```python
SILKY_MAX_RECORDED_REQUESTS = 1000
SILKY_MAX_RECORDED_REQUESTS_CHECK_PERCENT = 10
```

## Dashboard

`http://localhost:8000/silk/`
