# Database

`django-environ` parses `DATABASE_URL`. No extra config beyond `DATABASES = {"default": env.db("DATABASE_URL")}`.

## SQLite

```sh
DATABASE_URL=sqlite:///db.sqlite3
```

No extra dependency. Add `db.sqlite3` to `.gitignore`.

### SQLite in production (optional — single-host, low/medium-traffic)

Modern SQLite + WAL handles real production load on a single VPS — one local file, no separate DB / cache / queue server. Trade-off: single host (no horizontal scaling), brief deploy blip without external replication. **Requires Django 5.1+** for the `transaction_mode` and `init_command` `OPTIONS` keys.

Override in `production.py` so dev keeps zero-config defaults:

```python
DATABASES["default"]["OPTIONS"] = {
    "transaction_mode": "IMMEDIATE",   # avoid SQLITE_BUSY under concurrent writers
    "timeout": 5,                      # seconds to wait on a locked DB
    "init_command": (
        "PRAGMA journal_mode=WAL;"          # writers don't block readers
        "PRAGMA synchronous=NORMAL;"        # safe with WAL, much faster than FULL
        "PRAGMA mmap_size=134217728;"       # 128 MiB memory-mapped reads
        "PRAGMA journal_size_limit=27103364;"
        "PRAGMA cache_size=2000;"           # pages (~ 8 MiB)
    ),
}
```

Django sets `PRAGMA foreign_keys=ON` for SQLite already.

Place the file on a persistent volume:

```sh
DATABASE_URL=sqlite:////data/site.sqlite3   # four slashes = absolute path
```

#### Cache on a separate SQLite

```python
DATABASES["cache"] = {
    "ENGINE": "django.db.backends.sqlite3",
    "NAME": "/data/cache.sqlite3",
    "OPTIONS": DATABASES["default"]["OPTIONS"],
}

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "cache_table",
    },
}

DATABASE_ROUTERS = ["config.routers.CacheRouter"]
```

`config/routers.py`:

```python
class CacheRouter:
    """Route django.core.cache reads/writes/migrations to the `cache` database."""
    label = "django_cache"

    def db_for_read(self, model, **hints):
        return "cache" if model._meta.app_label == self.label else None

    def db_for_write(self, model, **hints):
        return "cache" if model._meta.app_label == self.label else None

    def allow_migrate(self, db, app_label, **hints):
        if app_label == self.label:
            return db == "cache"
        return None
```

Once during deploy:

```sh
uv run manage.py createcachetable --database cache
```

#### Background tasks on SQLite

`django-tasks-db` (`references/tasks-django.md` Backend A) runs against the default DB, no broker needed. Other no-broker options: `django-q2`, `huey` (DB consumer mode).

#### Backup — Litestream

[Litestream](https://litestream.io) streams every WAL frame to S3-compatible storage (R2, B2, Hetzner Object Storage, AWS S3). The container restores from the bucket on boot, then `litestream replicate` wraps `gunicorn`.

Production `Dockerfile`:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends wget \
 && wget -q https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.deb \
 && dpkg -i litestream-v0.3.13-linux-amd64.deb \
 && rm litestream-v0.3.13-linux-amd64.deb \
 && rm -rf /var/lib/apt/lists/*
```

`litestream.yml`:

```yaml
dbs:
  - path: /data/site.sqlite3
    replicas:
      - type: s3
        endpoint: ${S3_ENDPOINT}
        bucket: ${S3_BUCKET}
        path: site/site.sqlite3
        access-key-id: ${S3_ACCESS_KEY_ID}
        secret-access-key: ${S3_SECRET_ACCESS_KEY}
```

`entrypoint.sh`:

```sh
#!/bin/sh
set -eu
mkdir -p /data
litestream restore -config /etc/litestream.yml -if-db-not-exists -if-replica-exists /data/site.sqlite3
python manage.py migrate --noinput
python manage.py createcachetable --database cache
exec litestream replicate -config /etc/litestream.yml -exec "gunicorn config.wsgi --bind 0.0.0.0:8000"
```

Trade-offs:

- **Gain**: no managed-DB cost, no network hop, simpler infra.
- **Watch**: single host (scale CPU/workers, not containers); deploys briefly stop writes during container swap.
- **Don't** pick this when you need horizontal write scaling, multi-region replicas, or strict zero-downtime — go PostgreSQL.

## PostgreSQL

```sh
uv add 'psycopg[binary]'
```

### Variant A — Postgres on host

```sh
createdb {project_slug}
```

`.env`:

```sh
DATABASE_URL=postgres://{user}:{password}@localhost:5432/{project_slug}
```

### Variant B — Postgres in Docker, Django on host

Run only the `db` service from `references/docker.md`:

```sh
docker compose up -d db
```

`.env` (host connects to the published port):

```sh
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
```

### Variant C — full stack in docker-compose

See `references/docker.md`. `.env` uses the service hostname:

```sh
DATABASE_URL=postgres://postgres:postgres@db:5432/postgres
```
