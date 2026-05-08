# Database

`django-environ` parses `DATABASE_URL` directly — no extra Django config beyond `DATABASES = {"default": env.db("DATABASE_URL")}`.

## SQLite (default, zero-setup)

`.env`:

```sh
DATABASE_URL=sqlite:///db.sqlite3
```

No extra dependency. The file lives next to `manage.py`. Add `db.sqlite3` to `.gitignore`.

### SQLite in production (optional — single-host, low/medium-traffic apps)

Modern SQLite + WAL handles real production load on a single VPS or container — no separate DB server, no separate cache, no separate queue broker, just one local file. Trade-off: a single host (no horizontal scaling) and a slight deployment-blip without an external replication tool. If that's acceptable, tune the connection. **Requires Django 5.1+** (the `transaction_mode` and `init_command` `OPTIONS` keys were added then).

Override `DATABASES["default"]` in `production.py` (after `env.db("DATABASE_URL")` parses the URL) so the production tuning doesn't apply in dev:

```python
DATABASES["default"]["OPTIONS"] = {
    "transaction_mode": "IMMEDIATE",   # avoid SQLITE_BUSY under concurrent writers
    "timeout": 5,                      # seconds to wait on a locked DB
    "init_command": (
        "PRAGMA journal_mode=WAL;"          # writers don't block readers
        "PRAGMA synchronous=NORMAL;"        # safe with WAL, much faster than FULL
        "PRAGMA mmap_size=134217728;"       # 128 MiB memory-mapped reads
        "PRAGMA journal_size_limit=27103364;"
        "PRAGMA cache_size=2000;"           # pages (≈ 8 MiB)
    ),
}
```

`PRAGMA foreign_keys=ON` is already set by Django for SQLite — no need to add it.

Place the SQLite file on a persistent disk / volume — not in the container's writable layer or the source tree:

```sh
DATABASE_URL=sqlite:////data/site.sqlite3   # four slashes = absolute path
```

#### Cache on SQLite

Django ships a `DatabaseCache` backend; pointing it at a *separate* SQLite file (so cache churn doesn't bloat the main DB and isn't backed up with it) is idiomatic:

```python
DATABASES["cache"] = {
    "ENGINE": "django.db.backends.sqlite3",
    "NAME": "/data/cache.sqlite3",
    "OPTIONS": DATABASES["default"]["OPTIONS"],   # same PRAGMAs
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

Run once during deploy:

```sh
uv run manage.py createcachetable --database cache
```

#### Background tasks on SQLite

If you chose **`django-tasks-db`** (`references/tasks-django.md`, Backend A), it already runs against the default DB — no broker needed, fits the SQLite-only philosophy. Other options that work without Redis: `django-q2`, `huey` (immediate or DB consumer mode).

#### Backup / replication — Litestream

Without replication, the SQLite file dies with the container. [Litestream](https://litestream.io) streams every WAL frame to S3-compatible storage (Cloudflare R2, Backblaze B2, Hetzner Object Storage, AWS S3). On boot, the container restores from the bucket, then `litestream replicate` wraps `gunicorn` so writes ship continuously.

Add to the production `Dockerfile` (after the uv steps):

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends wget \
 && wget -q https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.deb \
 && dpkg -i litestream-v0.3.13-linux-amd64.deb \
 && rm litestream-v0.3.13-linux-amd64.deb \
 && rm -rf /var/lib/apt/lists/*
```

`litestream.yml` (env-driven credentials):

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

Boot order in `entrypoint.sh`:

```sh
#!/bin/sh
set -eu
mkdir -p /data
litestream restore -config /etc/litestream.yml -if-db-not-exists -if-replica-exists /data/site.sqlite3
python manage.py migrate --noinput
python manage.py createcachetable --database cache
exec litestream replicate -config /etc/litestream.yml -exec "gunicorn config.wsgi --bind 0.0.0.0:8000"
```

Re-cap of trade-offs:

- **Yes:** dramatically simpler infra, no managed-DB cost, no network hop, fast.
- **Watch out:** single host (scale by adding workers / CPU, not containers); deploys briefly stop writes during the container swap (Coolify / CapRover / Caddy zero-downtime mitigates); no point-in-time recovery beyond Litestream's WAL stream.
- **Don't pick this** when you genuinely need horizontal write scaling, multi-region replicas, or strict zero-downtime deploys — go PostgreSQL.

## PostgreSQL

```sh
uv add 'psycopg[binary]'
```

### Variant A — Postgres on host

Create the DB once:

```sh
createdb {project_slug}
# or:  psql -c "CREATE DATABASE {project_slug};"
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

See `references/docker.md` "Local development". `.env` uses the service hostname:

```sh
DATABASE_URL=postgres://postgres:postgres@db:5432/postgres
```
