# WhiteNoise

Production-only — keep the middleware out of `base.py` so `runserver`'s static-file handler stays in charge during local development.

```toml
# pyproject.toml
dependencies = [
    "whitenoise",
]
```

```python
# config/settings/production.py
from .base import MIDDLEWARE as _BASE_MIDDLEWARE

MIDDLEWARE = [
    _BASE_MIDDLEWARE[0],                                # SecurityMiddleware
    "whitenoise.middleware.WhiteNoiseMiddleware",       # must come right after SecurityMiddleware
    *_BASE_MIDDLEWARE[1:],
]

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}
```

`CompressedManifestStaticFilesStorage` writes hashed + gzipped copies during `collectstatic`. The Dockerfile must run `collectstatic --noinput` with `DJANGO_SETTINGS_MODULE=config.settings.production` so the manifest exists before gunicorn boots.
