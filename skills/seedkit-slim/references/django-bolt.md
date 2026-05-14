# django-bolt

Rust-powered API framework. Runs its own HTTP server via `manage.py runbolt`. Pin a version — pre-1.0.

```sh
uv add django-bolt msgspec
```

`msgspec` is a transitive dep, but `api/api.py` imports it directly — pin it so the lockfile records it as a runtime dep.

No aarch64-linux wheel is published. Docker builds on Apple Silicon compile the Rust extension from source — the builder stage needs the toolchain:

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*
```

The runtime stage stays on `python:3.12-slim-bookworm`.

`config/urls_bolt.py` — BoltAPI auto-discovers handlers, but Django's URL conf check still requires `urlpatterns`:

```python
urlpatterns: list = []
```

`INSTALLED_APPS += ['django_bolt']` — unlike `django-modern-rest`, this one is a Django app (ships `runbolt`). The app that holds `api.py` (e.g. `"api"`) must also be in `INSTALLED_APPS` — bolt auto-discovery scans installed apps for `api.py`.

## Handler shape

```python
# api/api.py
import msgspec
from django_bolt import BoltAPI, Response
from django.contrib.auth import get_user_model

api = BoltAPI()
User = get_user_model()

class UserOut(msgspec.Struct):
    id: int
    username: str

@api.get("/users/{user_id}")
async def get_user(user_id: int):  # no return annotation — bolt validates return type and rejects union (`UserOut | Response`)
    try:
        user = await User.objects.aget(id=user_id)
    except User.DoesNotExist:
        return Response({"detail": "not found"}, status_code=404)  # status_code=, not status=
    return UserOut(id=user.id, username=user.username)
```
