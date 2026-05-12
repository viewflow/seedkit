# Docker

Docs: <https://docs.astral.sh/uv/guides/integration/docker/> · <https://docs.docker.com/compose/>

The skill asks the user up-front (Foundation step 4) which structure to use:

- **`simple`** — separate `Dockerfile.dev` + separate production `Dockerfile`, single `docker-compose.yml`. Easier to read, two files can drift. **Default.**
- **`override`** — one multi-stage `Dockerfile` with `dev` and `prod` targets, `docker-compose.yml` (prod-shaped) + `docker-compose.override.yml` (dev layer, auto-loaded by `docker compose`). One source of truth; dev and prod can't silently diverge.

The same choice applies in production — don't re-ask. The "Local development" and "Production" sections below each have a **simple** subsection (default) and an **override** subsection.

## Image choice

Use these three across every `FROM` in this reference. Don't substitute Alpine, distroless, or the full (non-slim) Debian.

| Tier | Image | Use it for |
|---|---|---|
| **Slim runtime** | `python:3.12-slim-bookworm` | Final stage of the multi-stage prod Dockerfile. Wheels-only deps; no compile here. |
| **Slim uv** *(default)* | `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` | Dev image, single-stage prod, builder stage of multi-stage. Handles every wheels-based Django project (`psycopg[binary]`, `pillow`, `cffi`). |
| **Full uv (escape hatch)** | `ghcr.io/astral-sh/uv:python3.12-bookworm` + `apt-get install -y --no-install-recommends build-essential libpq-dev default-libmysqlclient-dev` | Only when a dep has no manylinux wheel: `mysqlclient`, `lxml` from source, certain hand-rolled `cffi` packages. |

Skip:
- `python:3.12-alpine` — musl breaks manylinux wheels, slow rebuilds, recurring CVE noise.
- `gcr.io/distroless/python3-debian12` — no shell, no apt, blocks `pg_dump` / `pg_isready` / debug.
- `python:3.12` (full Debian) — never; slim covers every wheels-based project.

Match the `python3.X` tag to `requires-python` in `pyproject.toml`. `uv sync --frozen` refuses to install on a mismatch.

## .dockerignore

`.dockerignore` for Django + uv. Always include `.venv` so the host venv doesn't leak into the image.

---

## Local development

`.venv` is baked into the image; source is bind-mounted for live reload; no named volume for the venv. Adding a dependency is a `docker compose build`, not a live `uv add` inside a running container.

### Simple — Dockerfile.dev

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

### Simple — docker-compose.yml

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
    # No host port mapping. `web` reaches `db` over the compose network;
    # publishing 5432 collides with any host-installed Postgres. Add a
    # localhost-only binding (e.g. "127.0.0.1:5433:5432") only when a host
    # GUI needs to connect.
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

For SQLite, drop the `db` service and `depends_on`, and mount a named volume on `web` so the DB file survives container recreation:

```yaml
services:
  web:
    # ...
    volumes:
      - .:/app
      - /app/.venv
      - sqlite_data:/data

volumes:
  sqlite_data:
```

`.env`: `DATABASE_URL=sqlite:////data/site.sqlite3` (four slashes = absolute path).

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
- **`web` healthcheck with `curl`** — the `uv:python3.12-bookworm-slim` image has no `curl`. `docker compose up -d --wait` doesn't need a `web` healthcheck (it waits on `running` for services without one); if you do add one, use the urllib form from `references/deploy-vps.md`.

### Override — multi-stage Dockerfile + compose override

One `Dockerfile` with two named targets (`dev` and `prod`). `docker-compose.yml` describes the prod-shaped stack and builds `target: prod`; `docker-compose.override.yml` is auto-loaded by `docker compose` and switches the `web` service to `target: dev`, mounts source, runs `runserver`. The same image definition serves both worlds — env-specific commands and mounts are layered on, not duplicated.

#### Dockerfile

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

COPY . .
RUN uv sync --frozen


FROM base AS dev
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]


FROM base AS prod
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system django && useradd --system --gid django django
RUN chown -R django:django /app

# Same S3 / DEBUG caveat as the single-stage variant below.
RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
    python manage.py collectstatic --noinput

USER django
CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000"]
```

`uv add gunicorn` before building the prod target — the `CMD` calls it directly.

#### docker-compose.yml (prod-shaped, committed)

```yaml
services:
  web:
    build:
      context: .
      target: prod
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

#### docker-compose.override.yml (dev layer, auto-loaded)

```yaml
services:
  web:
    build:
      target: dev
    volumes:
      - .:/app          # source live-reload
      - /app/.venv      # anonymous volume shadows host .venv

  db:
    # No host port mapping. `web` reaches `db` over the compose network;
    # publishing 5432 collides with any host-installed Postgres. Add a
    # localhost-only binding (e.g. "127.0.0.1:5433:5432") only when a host
    # GUI needs to connect.
```

`docker compose up` in dev merges both files automatically. CI / production runs `docker compose -f docker-compose.yml up` (no override) to get the prod build.

For SQLite, drop the `db` service from both files (and `depends_on` on `web`), and add a named volume on `web` in `docker-compose.yml`:

```yaml
services:
  web:
    # ...
    volumes:
      - sqlite_data:/data

volumes:
  sqlite_data:
```

`.env`: `DATABASE_URL=sqlite:////data/site.sqlite3`.

#### Boot check

Identical to the simple path:

```sh
docker compose up -d --build
docker compose exec web python manage.py migrate
docker compose exec web python manage.py createsuperuser
```

---

## Production

**Add the production server before building the image:**

```sh
uv add gunicorn
```

The Dockerfile's `CMD` calls `gunicorn` directly. Without this step it's not in `pyproject.toml` / `uv.lock` and the image build skips it; the container then exits with `gunicorn: not found`.

**Match the `python3.X` image tag to `requires-python` in `pyproject.toml`** — `uv sync --frozen` refuses to install on a mismatch.

**If the user picked `override` in Foundation step 4**, the production image is the `prod` target of the multi-stage Dockerfile shown in *Local development → Override*. Skip the variants below — they apply only to the `simple` path.

**Simple path only — ask the user**: does image size matter? Multi-stage saves ~150 MB at the cost of a more complex Dockerfile. Default to single-stage.

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

CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000"]
```

Runtime uses `python:3.12-slim` — no uv binary, no build cache. ~100–200 MB lighter.

### Optional — BuildKit cache mount

Speeds up CI rebuilds when `uv.lock` is unchanged:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
```

### Waiting for Postgres

No `entrypoint.sh`, no `pg_isready` loop. Compose's
`depends_on: condition: service_healthy` (already wired on the `db` service)
gates `web` startup until Postgres reports healthy. Migrations run as an
explicit one-shot — see `references/deploy-vps.md` and
`references/deploy-github-ssh.md`:

```sh
docker compose -f deploy/docker-compose.prod.yml run --rm web manage.py migrate
```

Keeping the container's job to "run gunicorn" makes restarts cheap, avoids
re-running migrations on every replica boot, and removes the
`pg_isready -d "$DATABASE_URL"` foot-gun (libpq URI scheme + missing-var
silent spin).
