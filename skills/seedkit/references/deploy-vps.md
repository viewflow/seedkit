# Deploy — VPS with Docker + Caddy

## deploy/docker-compose.prod.yml

```yaml
services:
  web:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - web

volumes:
  pgdata:
  caddy_data:
  caddy_config:
```

## deploy/Caddyfile

```
example.com {
    reverse_proxy web:8000
}
```

The Caddyfile only proxies. WhiteNoise inside the `web` container handles `/static/`. Don't add a `handle /static/*` block pointing at a host path — `web` is the only thing that has the collected files (they live inside the image), so a Caddy block would 404.

If the project also serves user-uploaded media via a shared volume (i.e. media on the VPS host, not S3 — see `references/storage-whitenoise.md`), serve it through Caddy:

```
example.com {
    handle /media/* {
        uri strip_prefix /media   # without this, file_server resolves /srv/media/media/<file>
        root * /srv/media
        file_server
    }
    reverse_proxy web:8000
}
```

Mount the same `media` named volume into the `caddy` service in `docker-compose.prod.yml` (`./media:/srv/media:ro`).

## Deploy

```sh
ssh user@vps
cd /srv/{project_slug}
git pull
docker compose -f deploy/docker-compose.prod.yml pull
docker compose -f deploy/docker-compose.prod.yml run --rm web uv run manage.py migrate
docker compose -f deploy/docker-compose.prod.yml up -d
```

Migrations run as a one-shot `docker compose run` *before* `up -d`. Don't generate an `entrypoint.sh` that bakes `migrate --noinput` and `pg_isready` loops into every container start — this re-runs migrations on every restart, races with concurrent web replicas on managed platforms, and the `pg_isready -d "$DATABASE_URL"` pattern is fragile (libpq honors only host/port from the URI; passing a full URI silently spins forever if the var is unset). Keep the deploy step explicit.
