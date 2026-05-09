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
    # AFTER SecurityMiddleware, not before. Prepending at index 0 routes
    # the profiler around Django's security headers on every request.
    sec_idx = MIDDLEWARE.index("django.middleware.security.SecurityMiddleware")
    MIDDLEWARE.insert(sec_idx + 1, "silk.middleware.SilkyMiddleware")
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

`silk` is removed from `INSTALLED_APPS` outside `DEBUG`, so its tables don't exist in production. A bare top-level `from silk.profiling.profiler import silk_profile` in app code raises at import on a prod boot; an unconditional `@silk_profile` decorator runs the profiling context manager and tries to write a `Request`/`Profile` row that has no table. Either pattern crashes prod.

Do **not** decorate app code with `@silk_profile` outright. The middleware above already profiles every request — that's enough for most cases.

If you need to profile a specific block:

```python
from django.conf import settings

if settings.DEBUG:
    from silk.profiling.profiler import silk_profile
else:
    def silk_profile(*_a, **_kw):
        def deco(fn):
            return fn
        return deco

@silk_profile(name="my expensive operation")
def expensive_operation():
    ...
```

For tasks under `django-tasks` / Celery, never stack `@silk_profile` outside `@task` — the task registry resolves the outer callable, so the worker would look up the silk wrapper instead of the task. Use the context-manager form inside the task body:

```python
from django.tasks import task

@task()
def send_welcome_email(user_id):
    with silk_profile(name="send_welcome_email"):
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
