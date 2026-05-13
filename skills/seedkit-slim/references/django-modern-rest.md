# django-modern-rest

```sh
uv add django-modern-rest pyjwt  # django-modern-rest imports jwt at module load even without JWT auth — missing pyjwt breaks `manage.py check`
```

```python
# settings.py
INSTALLED_APPS = [
    # ...
    "modern_rest",
]
```

Controllers live in `<app>/controllers.py`; request schemas use `msgspec.Struct`. Mount the router in `config/urls.py`:

```python
from modern_rest import Router
from api.controllers import MediaController

router = Router()
router.register(MediaController)

urlpatterns = [
    # ...
    path("api/", router.urls),
]
```
