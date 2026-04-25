# Docker

## .dockerignore

Create `.dockerignore` for Django + uv.

## Dockerfile

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system django && useradd --system --gid django django

WORKDIR /app

COPY --chown=django:django pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY --chown=django:django . .

RUN uv run manage.py collectstatic --noinput

USER django

ENTRYPOINT ["./entrypoint.sh"]
CMD ["uv", "run", "gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000"]
```

## entrypoint.sh

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

## docker-compose.yml

```yaml
services:
  web:
    build: .
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

## .env

```sh
DATABASE_URL=postgres://postgres:postgres@db:5432/postgres
```

## Run

```sh
docker compose up --build
docker compose run --rm web uv run manage.py migrate
docker compose run --rm web uv run manage.py createsuperuser
```
