# Storage — WhiteNoise + Local Media

WhiteNoise serves **static files only** (CSS, JS, images bundled with the app). User-uploaded media files are served separately.

- **VPS**: media served by Caddy from a Docker volume
- **Managed platforms**: media files don't survive redeployment on ephemeral filesystems — use `storage-s3.md` for user uploads

## Install

```sh
uv add whitenoise
```

## config/settings/base.py (or settings.py for single-file)

Insert `whitenoise.middleware.WhiteNoiseMiddleware` into the **existing** `MIDDLEWARE` list — directly after `SecurityMiddleware`. Do not redeclare the full list.

Add the rest below (no `STORAGES` here yet — see next section):

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
```

## config/settings/production.py

Manifest static storage requires `collectstatic` to have run, so it breaks `runserver` in dev. Configure it in production only:

```python
STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}
```

(Single-file layout: gate the same dict on `not DEBUG`, or skip the `STORAGES` override entirely until you deploy.)

The `CompressedManifestStaticFilesStorage` backend is the **only** switch needed for compression + hashed filenames. Don't invent `WHITENOISE_COMPRESS` / `WHITENOISE_USE_FINDERS` — they don't exist.

The `STORAGES` dict (Django 4.2+) replaces the legacy `STATICFILES_STORAGE` and `DEFAULT_FILE_STORAGE` settings. Use `STORAGES` only — never set the legacy keys alongside it.

## config/urls.py

Add at the bottom so Django serves media in local development:

```python
from django.conf import settings
from django.conf.urls.static import static

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

## VPS — docker-compose.prod.yml

Add a shared `media` volume between `web` and `caddy`:

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

Static files are served by WhiteNoise directly from the container — no extra configuration needed.

Media files (user uploads) require external storage because managed platforms use ephemeral filesystems. Use `storage-s3.md` to add S3-compatible storage for media.
