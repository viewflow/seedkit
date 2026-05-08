# Storage — S3

Stores both static and media files in an S3-compatible bucket. Works on all deployment targets including managed platforms with ephemeral filesystems.

Compatible providers: AWS S3, DigitalOcean Spaces, Cloudflare R2, Backblaze B2, MinIO.

## Install

```sh
uv add django-storages[s3]
```

## config/settings/base.py

This block **replaces** any `STATIC_URL` / `STATIC_ROOT` / `MEDIA_URL` / `MEDIA_ROOT` set in the foundation. With S3 there's no local `STATIC_ROOT` — `collectstatic` writes straight to the bucket.

The `STORAGES` dict (Django 4.2+) replaces the legacy `STATICFILES_STORAGE` and `DEFAULT_FILE_STORAGE` settings. Use `STORAGES` only — never set the legacy keys alongside it.

```python
AWS_ACCESS_KEY_ID = env("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = env("AWS_SECRET_ACCESS_KEY")
AWS_STORAGE_BUCKET_NAME = env("AWS_STORAGE_BUCKET_NAME")
AWS_S3_REGION_NAME = env("AWS_S3_REGION_NAME", default="us-east-1")
# For S3-compatible providers (MinIO, R2, B2, Spaces) — set the endpoint
# and skip AWS_S3_CUSTOM_DOMAIN so django-storages signs URLs against
# the endpoint. AWS-only deployments should set AWS_S3_CUSTOM_DOMAIN.
AWS_S3_ENDPOINT_URL = env("AWS_S3_ENDPOINT_URL", default="")
AWS_S3_CUSTOM_DOMAIN = env("AWS_S3_CUSTOM_DOMAIN", default="")

STORAGES = {
    "default": {
        "BACKEND": "storages.backends.s3boto3.S3Boto3Storage",
        "OPTIONS": {"location": "media"},
    },
    "staticfiles": {
        "BACKEND": "storages.backends.s3boto3.S3StaticStorage",
        "OPTIONS": {"location": "static"},
    },
}

# When AWS_S3_CUSTOM_DOMAIN is set (real AWS / CloudFront) we can hardcode
# the URL prefix; otherwise let django-storages generate URLs against the
# endpoint, which is correct for MinIO and other compatibles.
if AWS_S3_CUSTOM_DOMAIN:
    STATIC_URL = f"https://{AWS_S3_CUSTOM_DOMAIN}/static/"
    MEDIA_URL = f"https://{AWS_S3_CUSTOM_DOMAIN}/media/"
```

## .env / .env.prod

```sh
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=...
AWS_S3_REGION_NAME=us-east-1
# AWS_S3_ENDPOINT_URL=http://minio:9000      # set for non-AWS providers
# AWS_S3_CUSTOM_DOMAIN=cdn.example.com       # set for real AWS + CloudFront
```

## Dockerfile

Remove `collectstatic` from the Dockerfile — it needs AWS credentials at build time which aren't available:

```dockerfile
# Remove this line:
# RUN uv run manage.py collectstatic --noinput
```

Run it instead as part of the deploy/release step.

## VPS — deploy script

Run `collectstatic` before starting containers:

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

Set the release command to:

```sh
uv run manage.py migrate && uv run manage.py collectstatic --noinput
```

Add the AWS env vars in the platform dashboard.
