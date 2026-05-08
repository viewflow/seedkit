# Redis

`django-redis` plugs Redis into Django's cache framework. Stock Django ships local-memory and DB cache backends only — neither survives a process restart or scales past one worker. Redis adds a shared, durable, fast cache plus the broker Celery and django-tasks-rq need.

## Install

```sh
uv add django-redis
```

## config/settings/base.py

Add after the `DATABASES` setting:

```python
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379")

# Use logical DBs to keep cache, broker, and result backend isolated:
# /0 cache, /1 Celery broker, /2 Celery results, /3 django-tasks-rq.
# A `cache.clear()` only affects DB 0; brokers / queues stay intact.
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": f"{REDIS_URL}/0",
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
    }
}
```

## Local — docker-compose.yml

Add `redis` service and update `web` depends_on:

```yaml
services:
  web:
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
```

Add to `.env`:

```sh
REDIS_URL=redis://redis:6379   # cache uses /0, Celery broker /1, results /2, RQ /3
```

## VPS — docker-compose.prod.yml

Add `redis` service and update `web` depends_on:

```yaml
services:
  web:
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
```

Add to `.env.prod`:

```sh
REDIS_URL=redis://redis:6379   # cache uses /0, Celery broker /1, results /2, RQ /3
```

## Managed platforms

**Fly.io** — managed Redis via Upstash:

```sh
fly redis create
fly redis attach <redis-name>
```

`REDIS_URL` is set automatically.

**Railway** — add Redis service from the dashboard. `REDIS_URL` is injected automatically as a shared variable.

**Render** — use [Upstash Redis](https://upstash.com/) (external). Copy the connection URL into the environment variables as `REDIS_URL`.
