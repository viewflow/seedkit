# Docker

## .dockerignore

`.dockerignore` for Django + uv. Always include `.venv` so the host venv doesn't leak into the image.

---

## Local development

`.venv` is baked into the image; source is bind-mounted for live reload; no named volume for the venv. Adding a dependency is a `docker compose build`, not a live `uv add` inside a running container.

### Dockerfile.dev

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

COPY . .
RUN uv sync --frozen

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
```

No `USER` switch (dev keeps root, simpler permissions). No `collectstatic` (`runserver` serves statics in DEBUG).

### docker-compose.yml

```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app          # source live-reload
      - /app/.venv      # anonymous volume shadows host .venv that the bind mount would otherwise leak in
    env_file: .env
    ports:
      - "8000:8000"
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
```

Drop the `db` service (and `depends_on`) for SQLite.

The `/app/.venv` line declares an anonymous volume at that path so the source bind-mount above can't overlay a host `.venv` on top of the image's. `.dockerignore` should also list `.venv` — belt and braces.

### Boot check

```sh
docker compose up -d --build
docker compose exec web python manage.py migrate
docker compose exec web python manage.py createsuperuser
```

`python manage.py` not `uv run manage.py`: `.venv/bin` is on `PATH`, no need for the wrapper.

Then open <http://localhost:8000/admin/>.

### Adding a dependency

```sh
# On the host:
uv add somepkg
docker compose build web
docker compose up -d
```

`uv add` updates `pyproject.toml` + `uv.lock` on the host; `docker compose build` rebuilds the image with the new lockfile. uv's BuildKit cache makes the rebuild fast (a few seconds) when only the lock changed.

### Pitfalls

- **`uv sync` hardlink warnings** — `UV_LINK_MODE=copy` (set in Dockerfile.dev) silences them.
- **Source edits not picked up** — confirm the bind-mount is `.:/app`, not a copy. `docker compose exec web ls /app` should show host changes immediately.
- **`Ignoring existing virtual environment linked to non-existent Python interpreter`** — means a host `.venv` slipped into the image build (missing `.dockerignore` entry) or the anonymous volume above isn't declared. Add `.venv` to `.dockerignore`, ensure the compose service has `- /app/.venv`, then `docker compose build --no-cache web`.

---

## Production

**Add the production server before building the image:**

```sh
uv add gunicorn
```

The Dockerfile's `CMD` calls `gunicorn` directly. Without this step it's not in `pyproject.toml` / `uv.lock` and the image build skips it; the container then exits with `gunicorn: not found`.

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
