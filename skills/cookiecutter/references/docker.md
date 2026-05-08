# Docker

## .dockerignore

Create `.dockerignore` for Django + uv. Always include `.venv` so the host venv (if any) doesn't leak into the image.

---

## Local development

Minimal compose for dev. Source is mounted; `runserver` reloads on edit.

### docker-compose.yml

Do not include a top-level `version:` field — Compose v2 ignores it and warns on every invocation.

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

Drop the `db` service (and `depends_on`) if using SQLite.

### Boot check

```sh
docker compose up -d
docker compose exec web uv run manage.py migrate
docker compose exec web uv run manage.py createsuperuser
```

Open <http://localhost:8000/admin/> and confirm login.

### Common pitfalls

- **`Permission denied` on `/home/<user>/.cache/uv`** — happens if `web` is built from the production Dockerfile (which sets `USER django`). The dev compose above uses the raw uv image; don't switch to `build: .` for dev.
- **`uv sync` hardlink warnings** — `UV_LINK_MODE: copy` silences them across mount boundaries.
- **Stale `.venv` from the host** — the named `venv` volume keeps the Linux venv separate. If you see `Ignoring existing virtual environment linked to non-existent Python interpreter`, the host venv leaked in (named volume missing from compose, or stale from an earlier run on a different OS). The warning is harmless — uv discards the broken venv and rebuilds a fresh Linux one — but if it persists, run `docker compose down -v` and rebuild so the named volume starts clean.

---

## Production

**Ask the user:** does image size matter? Smaller image (multi-stage, ~150 MB lighter) trades build complexity for a leaner runtime. Default to single-stage unless they say yes.

Both variants share these uv best-practice flags (per <https://docs.astral.sh/uv/guides/integration/docker/>):

- `UV_COMPILE_BYTECODE=1` — pre-compile `.pyc` for faster cold start.
- `UV_LINK_MODE=copy` — avoid hardlink errors across cache/bind mounts.
- Two-step `uv sync`: deps first (`--no-install-project`), then project after `COPY .` — maximises layer cache.
- `PATH=/app/.venv/bin:$PATH` — call `gunicorn` directly, skip `uv run` overhead at every container start.

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

# DJANGO_DEBUG=True unlocks dev defaults so collectstatic can import settings
# without real SECRET_KEY / DATABASE_URL. Not used at runtime.
RUN DJANGO_DEBUG=True python manage.py collectstatic --noinput

USER django

ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000"]
```

### Variant B — multi-stage (smaller runtime image)

```dockerfile
# --- builder ---
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY . .
RUN uv sync --frozen --no-dev

RUN DJANGO_DEBUG=True /app/.venv/bin/python manage.py collectstatic --noinput

# --- runtime ---
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

The runtime stage uses the plain `python:3.12-slim` image — no uv binary, no build cache. Roughly 100–200 MB lighter depending on dependencies.

### Optional: BuildKit cache mount

To speed up rebuilds in CI (skips re-downloading wheels when `uv.lock` is unchanged), replace the first `uv sync` with:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
```

Requires BuildKit (default in modern Docker).

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
