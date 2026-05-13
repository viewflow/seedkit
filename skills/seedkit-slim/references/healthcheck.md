# Health check endpoints

Two trivial views beat pulling `django-health-check` (which adds 8 backends, a class-based settings shape, and a multi-app `INSTALLED_APPS` block).

Put them in `config/views.py` (or any registered app's `views.py`):

```python
from django.db import connection
from django.db.utils import OperationalError
from django.http import HttpResponse


def liveness(_request):
    return HttpResponse('ok', content_type='text/plain')


def readiness(_request):
    try:
        with connection.cursor() as cur:
            cur.execute('SELECT 1')
    except OperationalError:
        return HttpResponse('db down', status=503, content_type='text/plain')
    return HttpResponse('ready', content_type='text/plain')
```

`config/urls.py` — no trailing slash; kubelets / Caddy / Fly call exactly `/healthz`:

```python
from config.views import liveness, readiness

urlpatterns = [
    # ...
    path('healthz', liveness, name='healthz'),
    path('readyz', readiness, name='readyz'),
]
```

When `SECURE_SSL_REDIRECT = True` is on in production, exempt the probe paths so the platform's internal HTTP probe doesn't get a 301:

```python
SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]
```
