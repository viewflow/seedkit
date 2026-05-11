# django-bolt

Docs: <https://django-bolt.readthedocs.io/>

Rust-powered API framework for Django. Runs its own HTTP server (Actix Web + PyO3 + msgspec), invoked through `manage.py runbolt`. Targets high-RPS JSON APIs while keeping access to Django ORM, admin, and packages.

Pre-1.0 — README explicitly says "under active development". Pin a version.

## Install

```sh
uv add django-bolt msgspec
```

`msgspec` is a transitive dep of `django-bolt`, but `api/api.py` imports it directly — pin it explicitly so the lockfile records it as a runtime dep.

The wheel includes a precompiled Rust extension. uv pulls the wheel on x86_64 / arm64 macOS and x86_64 Linux without a toolchain. **No aarch64-linux wheel** is published — Docker builds on Apple Silicon (linux/arm64 platform) compile from source. Every stage that runs `uv sync` (builder for the `simple` multi-stage Dockerfile; both `dev` and `prod` for the `override` Dockerfile, since they share the `base` stage that does `uv sync`) must use the full uv image plus build tools — see `references/docker.md` "Full uv (escape hatch)" tier:

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*
```

The slim runtime stage stays on `python:3.12-slim-bookworm` — only stages that run `uv sync` need the toolchain. For the `override` Dockerfile, switch the shared `base` stage to the full uv image with `build-essential pkg-config`; both `dev` and `prod` inherit it.

## settings.py / base.py

Add the Django app:

```python
INSTALLED_APPS = [
    # ...
    'django_bolt',
]
```

(Unlike `django-modern-rest`, this one *is* a Django app — it ships management commands, including `runbolt`.)

## Layout

API definitions live inside a registered Django app, not at project root. Create one if needed: `uv run manage.py startapp api`.

```
api/
  __init__.py
  apps.py
  api.py        # BoltAPI() instance + routes
  schemas.py    # msgspec.Struct models
```

## Minimal endpoint — `api/api.py`

```python
import msgspec
from django.contrib.auth import get_user_model
from django_bolt import BoltAPI

User = get_user_model()
api = BoltAPI()


class UserSchema(msgspec.Struct):
    id: int
    username: str


@api.get('/users/{user_id}')
async def get_user(user_id: int) -> UserSchema:
    user = await User.objects.aget(id=user_id)
    return UserSchema(id=user.id, username=user.username)
```

Schemas must be `msgspec.Struct` — django-bolt is bound to msgspec and does not accept pydantic.

## Running

Two servers, two ports:

- `python manage.py runserver` — admin, classic Django views.
- `python manage.py runbolt --dev` — Bolt API on its own port.

Document both in `README.md`. In production, deploy `runbolt` behind the same reverse proxy as gunicorn (different upstream blocks, different paths). The README states "no gunicorn or uvicorn needed" for the Bolt side specifically.

## Fast-path settings (optional, advanced)

By default, `runbolt` and `runserver` / `gunicorn` share the same settings module — process separation comes for free, settings separation is a second, opt-in step. Only do this if RPS was the explicit reason for picking django-bolt over django-modern-rest. The cost is two settings modules that can drift: every new app, signal, or middleware added to `base.py` requires a conscious decision about whether the bolt process needs it.

Add `config/settings/bolt.py` that imports from `base` and strips what the API path doesn't need:

```python
from .base import *
from .base import INSTALLED_APPS, MIDDLEWARE

# Auth happens in Rust (JWT / API key) — Django auth middleware adds no value.
# Sessions / messages / CSRF only apply to browser flows that don't reach bolt.
_DROP_MIDDLEWARE = {
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
}
MIDDLEWARE = [m for m in MIDDLEWARE if m not in _DROP_MIDDLEWARE]

# Admin / sessions / messages / staticfiles aren't served by bolt.
_DROP_APPS = {
    'django.contrib.admin',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
}
INSTALLED_APPS = [a for a in INSTALLED_APPS if a not in _DROP_APPS]

# No HTML rendering on the API path.
TEMPLATES = []

ROOT_URLCONF = 'config.urls_bolt'  # API-only URLConf, no admin / accounts
```

`config/urls_bolt.py` is the API-only URLConf. `runbolt` discovers routes from the `BoltAPI()` instances directly — `BoltAPI` has no `.urls` attribute to mount, so the URLConf stays empty:

```python
# config/urls_bolt.py
urlpatterns: list = []
```

Keep `config/urls.py` as the full URLConf for `runserver` / `gunicorn`.

Run bolt against the slim settings; leave the full stack on the regular settings:

```sh
# API process (high RPS path)
DJANGO_SETTINGS_MODULE=config.settings.bolt python manage.py runbolt --dev

# Admin / classic views (separate process, full middleware stack)
python manage.py runserver
```

In production: same split — bolt service uses `DJANGO_SETTINGS_MODULE=config.settings.bolt`, gunicorn uses `config.settings.production`. Reverse proxy routes `/api/*` to bolt, everything else to gunicorn.

### When NOT to do this

- The user picked bolt without a specific RPS target — keep one settings module, skip this.
- The API touches `request.user` via `django.contrib.auth` (sessions). The fast-path drops auth middleware; only viable when auth is fully token-based and validated in Rust.
- The team is small and the drift cost outweighs the per-request savings.

## Auth

`django-bolt` validates JWT / API keys in Rust without taking the Python GIL. Configuration goes through its own settings — see https://bolt.farhana.li/topics/authentication/. Do **not** wire DRF-style auth classes; they don't apply.

If the user picked `django-allauth` / `django-mail-auth` for the Django side, those continue to handle session / magic-link auth on the `runserver` side. The Bolt side uses tokens.

## OpenAPI

Auto-generated. The library ships Swagger, ReDoc, Scalar, and RapidDoc UIs — pick one in settings. Gate the docs UI on `DEBUG` unless a public schema is wanted.

## Boot check

Standard `migrate` + `createsuperuser` first. Then verify the Bolt server boots:

```sh
python manage.py runbolt --dev &
sleep 1
curl -sf http://127.0.0.1:8000/users/1
```

(Adjust the port to whatever `runbolt --dev` reports.)

## Pitfalls

- Two HTTP servers in dev — make sure the user understands `runserver` and `runbolt` are different processes.
- Production deploy: the production Dockerfile must expose / launch `runbolt`, not gunicorn, for the API path. Update `references/docker.md` snippets accordingly when both are present.
- msgspec-only — if the user wants pydantic, they want `django-modern-rest`, not `django-bolt`.
- Pre-1.0; pin the version.
