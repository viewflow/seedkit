# django-modern-rest

```sh
uv add 'django-modern-rest[msgspec,openapi]' pyjwt  # the package imports `jwt` at module load even without JWT auth — missing pyjwt breaks `manage.py check`
```

The installed Python package is `dmr`, not `modern_rest`. Do NOT add `dmr` to `INSTALLED_APPS` — it ships no apps.

## Schemas

```python
# api/schemas.py
import msgspec

class MediaCreate(msgspec.Struct):
    filename: str
    size: int

class MediaOut(msgspec.Struct):
    uid: str
    filename: str
```

## Controller

```python
# api/controllers.py
import uuid
from dmr import Body, Controller
from api.schemas import MediaCreate, MediaOut

class MediaController(Controller):
    def post(self, parsed_body: Body[MediaCreate]) -> MediaOut:
        return MediaOut(uid=str(uuid.uuid4()), filename=parsed_body.filename)
```

HTTP-verb method names (`get` / `post` / `put` / `delete`) dispatch automatically — no decorator registration.

## Router

```python
# api/urls.py
from django.urls import path
from dmr.routing import Router
from api.controllers import MediaController

router = Router("api/", [path("media/", MediaController.as_view())])
urlpatterns = router.urls
```

```python
# config/urls.py
from django.urls import include, path
urlpatterns = [
    # ...
    path("", include("api.urls")),  # Router already carries the "api/" prefix
]
```
