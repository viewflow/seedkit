# Storage — WhiteNoise + Local Media

WhiteNoise serves **static files only** (CSS, JS, images bundled with the app). User-uploaded media files are served separately.

- **VPS**: media served by Caddy from a Docker volume
- **Managed platforms**: media files don't survive redeployment on ephemeral filesystems — use `storage-s3.md` for user uploads

## Install

```sh
uv add whitenoise
```

## config/settings/base.py

```python
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",  # right after SecurityMiddleware
    ...
]

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

STORAGES = {
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"
```

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
