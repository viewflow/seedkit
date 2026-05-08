# Storage — WhiteNoise + Local Media

WhiteNoise serves **static files only**. User-uploaded media goes elsewhere:

- **VPS**: Caddy serves media from a Docker volume.
- **Managed platforms**: ephemeral filesystems lose media on redeploy — use `storage-s3.md`.

## Install

```sh
uv add whitenoise
```

## Settings — base / single-file

Insert `whitenoise.middleware.WhiteNoiseMiddleware` into the **existing** `MIDDLEWARE` directly after `SecurityMiddleware`. Don't redeclare the list.

Then:

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
```

## Settings — production.py

Manifest storage requires `collectstatic` to have run, so it breaks `runserver` in dev. Configure it production-only:

```python
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}
```

(Single-file layout: gate on `not DEBUG`, or skip until deploy.)

`CompressedManifestStaticFilesStorage` is the only switch needed for compression + hashed filenames. `WHITENOISE_COMPRESS` / `WHITENOISE_USE_FINDERS` don't exist.

`STORAGES` (Django 4.2+) replaces legacy `STATICFILES_STORAGE` and `DEFAULT_FILE_STORAGE`. Don't set the legacy keys alongside it.

## config/urls.py

Serve media in dev:

```python
from django.conf import settings
from django.conf.urls.static import static

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

## VPS — docker-compose.prod.yml

Shared `media` volume between `web` and `caddy`:

```yaml
services:
  web:
    volumes:
      - media:/app/media

  caddy:
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
      - media:/srv/media:ro

volumes:
  pgdata:
  caddy_data:
  caddy_config:
  media:
```

## VPS — Caddyfile

```
example.com {
    handle /media/* {
        root * /srv/media
        file_server
    }
    reverse_proxy web:8000
}
```

## Managed platforms

WhiteNoise serves static from the container — nothing extra. Media on managed platforms needs external storage; use `storage-s3.md`.
