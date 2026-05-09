# Storage — S3

Static and media in an S3-compatible bucket. Works on every deploy target including managed platforms with ephemeral filesystems.

Compatible providers: AWS S3, DigitalOcean Spaces, Cloudflare R2, Backblaze B2, MinIO.

## Install

```sh
uv add django-storages[s3]
```

## Settings

This block **replaces** any `STATIC_URL` / `STATIC_ROOT` / `MEDIA_URL` / `MEDIA_ROOT` set in the foundation. With S3 there's no local `STATIC_ROOT` — `collectstatic` writes straight to the bucket.

`STORAGES` (Django 4.2+) replaces legacy `STATICFILES_STORAGE` / `DEFAULT_FILE_STORAGE`. Don't set the legacy keys alongside it.

```python
# Gated defaults match the foundation pattern: dev/build runs zero-config,
# prod (DEBUG unset) raises ImproperlyConfigured if any of these is missing.
AWS_ACCESS_KEY_ID     = env("AWS_ACCESS_KEY_ID",     default="" if DEBUG else None)
AWS_SECRET_ACCESS_KEY = env("AWS_SECRET_ACCESS_KEY", default="" if DEBUG else None)
AWS_STORAGE_BUCKET_NAME = env("AWS_STORAGE_BUCKET_NAME", default="" if DEBUG else None)
AWS_S3_REGION_NAME = env("AWS_S3_REGION_NAME", default="us-east-1")
# Non-AWS providers (MinIO, R2, B2, Spaces): set the endpoint, skip
# AWS_S3_CUSTOM_DOMAIN so django-storages signs URLs against the endpoint.
AWS_S3_ENDPOINT_URL  = env("AWS_S3_ENDPOINT_URL",  default="")
AWS_S3_CUSTOM_DOMAIN = env("AWS_S3_CUSTOM_DOMAIN", default="")

# Media to S3 in every environment (MinIO in dev, real S3 in prod).
# Static stays on Django's local backend in base — collectstatic + admin
# CSS work in `runserver` without bucket creds. production.py flips static
# to S3 for real deploys.
STORAGES = {
    "default": {
        "BACKEND": "storages.backends.s3boto3.S3Boto3Storage",
        "OPTIONS": {"location": "media"},
    },
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
    },
}

STATIC_URL = "/static/"
MEDIA_URL  = f"https://{AWS_S3_CUSTOM_DOMAIN}/media/" if AWS_S3_CUSTOM_DOMAIN else "/media/"
```

In `config/settings/production.py`, flip static to S3:

```python
STORAGES = {
    **STORAGES,
    "staticfiles": {
        "BACKEND": "storages.backends.s3boto3.S3StaticStorage",
        "OPTIONS": {"location": "static"},
    },
}

if AWS_S3_CUSTOM_DOMAIN:
    STATIC_URL = f"https://{AWS_S3_CUSTOM_DOMAIN}/static/"
```

## .env / .env.prod

```sh
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=...
AWS_S3_REGION_NAME=us-east-1
# AWS_S3_ENDPOINT_URL=http://minio:9000      # non-AWS providers
# AWS_S3_CUSTOM_DOMAIN=cdn.example.com       # AWS + CloudFront
```

## Dockerfile — remove build-time collectstatic

The Dockerfile in `references/docker.md` runs `collectstatic` at build. That works for WhiteNoise (local dir baked in) but **fails for S3** — collectstatic uploads to the bucket and needs real AWS credentials, which must not enter the build context. Delete the line:

```dockerfile
# Delete this RUN — collectstatic moves to deploy.
# RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
#     /app/.venv/bin/python manage.py collectstatic --noinput
```

Run `collectstatic` at deploy with real env vars. Patterns below.

## VPS — deploy script

```sh
ssh user@vps
cd /srv/{project_slug}
git pull
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml run --rm web uv run manage.py collectstatic --noinput
docker compose -f docker-compose.prod.yml run --rm web uv run manage.py migrate
docker compose -f docker-compose.prod.yml up -d
```

## Managed — fly.toml

```toml
[deploy]
  release_command = "uv run manage.py migrate && uv run manage.py collectstatic --noinput"
```

## Managed — Railway / Render

Release command:

```sh
uv run manage.py migrate && uv run manage.py collectstatic --noinput
```

AWS env vars go in the platform dashboard.
