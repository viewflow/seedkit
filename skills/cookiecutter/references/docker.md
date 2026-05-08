# Docker

## .dockerignore

`.dockerignore` for Django + uv. Always include `.venv` so the host venv doesn't leak into the image.

---

## Local development

Source mounted, `runserver` reloads on edit.

### docker-compose.yml

No top-level `version:` — Compose v2 ignores it and warns.

```yaml
services:
  web:
    image: ghcr.io/astral-sh/uv:python3.12-bookworm-slim
    working_dir: /app
    environment:
      UV_CACHE_DIR: /tmp/uv-cache
      UV_LINK_MODE: copy
    volumes:
      - .:/app
      - venv:/app/.venv          # isolate Linux venv from host (macOS/Windows)
      - uv-cache:/tmp/uv-cache   # writable cache for any user
    env_file: .env
    ports:
      - "8000:8000"
    command: sh -c "uv sync && uv run manage.py runserver 0.0.0.0:8000"
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  venv:
  uv-cache:
```

Drop the `db` service (and `depends_on`) for SQLite.

### Boot check

```sh
docker compose up -d
docker compose exec web uv run manage.py migrate
docker compose exec web uv run manage.py createsuperuser
```

Then open <http://localhost:8000/admin/>.

### Pitfalls

- **`Permission denied` on `/home/<user>/.cache/uv`** — happens if `web` is built from the production Dockerfile (`USER django`). Keep dev on the raw uv image; don't `build: .` for dev.
- **`uv sync` hardlink warnings** — `UV_LINK_MODE: copy` silences them.
- **`Ignoring existing virtual environment linked to non-existent Python interpreter`** — host `.venv` leaked in (named volume missing or stale). Harmless (uv rebuilds the venv); if it persists, `docker compose down -v` and rebuild.

---

## Production

**Match the `python3.X` image tag to `requires-python` in `pyproject.toml`** — `uv sync --frozen` refuses to install on a mismatch.

**Ask the user**: does image size matter? Multi-stage saves ~150 MB at the cost of a more complex Dockerfile. Default to single-stage.

Both variants apply the [astral-sh uv-in-Docker](https://docs.astral.sh/uv/guides/integration/docker/) flags:

- `UV_COMPILE_BYTECODE=1` — pre-compile `.pyc` for faster cold start.
- `UV_LINK_MODE=copy` — silence hardlink errors across mounts.
- Two-step `uv sync`: deps (`--no-install-project`) before `COPY .`, project after.
- `PATH=/app/.venv/bin:$PATH` — call `gunicorn` directly, skip `uv run`.

### Variant A — single-stage (default)

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system django && useradd --system --gid django django

WORKDIR /app

COPY --chown=django:django pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY --chown=django:django . .
RUN uv sync --frozen --no-dev

# DELETE this RUN if storage is S3 (collectstatic needs bucket creds at
# deploy time, not build). See references/storage-s3.md.
# DJANGO_DEBUG=True unlocks dev defaults so collectstatic boots without
# real SECRET_KEY / DATABASE_URL. SETTINGS_MODULE → production so STORAGES
# (manifest static storage) applies; otherwise manage.py uses local.py.
RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
    python manage.py collectstatic --noinput

USER django

ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000"]
```

### Variant B — multi-stage (smaller runtime image)

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY . .
RUN uv sync --frozen --no-dev

# Same S3 caveat as variant A.
RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
    /app/.venv/bin/python manage.py collectstatic --noinput

FROM python:3.12-slim-bookworm AS runtime
ENV PATH="/app/.venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system django && useradd --system --gid django django

WORKDIR /app
COPY --from=builder --chown=django:django /app /app

USER django

ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000"]
```

Runtime uses `python:3.12-slim` — no uv binary, no build cache. ~100–200 MB lighter.

### Optional — BuildKit cache mount

Speeds up CI rebuilds when `uv.lock` is unchanged:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
```

### entrypoint.sh

```sh
#!/bin/sh
set -e

until pg_isready -d "$DATABASE_URL" -q; do
    sleep 1
done

exec "$@"
```

```sh
chmod +x entrypoint.sh
```
