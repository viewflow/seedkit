# Deploy — VPS with Docker + Caddy

Docs: <https://caddyserver.com/docs/> · <https://docs.docker.com/compose/>

## deploy/docker-compose.prod.yml

```yaml
services:
  web:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    env_file: .env.prod
    healthcheck:
      # python+urllib instead of curl — the prod image only installs
      # postgresql-client and slim has no curl.
      test: ["CMD-SHELL", "python -c 'import urllib.request,sys; sys.exit(0 if urllib.request.urlopen(\"http://localhost:8000/healthz\",timeout=2).status==200 else 1)'"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s
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
example.com {     # replace with the real domain — Caddy fails to issue TLS for example.com
    reverse_proxy web:8000 {
        # Probe `/healthz` (process up) — NOT `/readyz` (DB+deps).
        # A transient DB blip on /readyz flips the upstream to "down" and
        # Caddy stops serving 200s; better to let /readyz feed monitoring
        # while the load-balancer probe stays liveness-only.
        health_uri /healthz
        health_interval 10s
        health_timeout 3s
    }
}
```

The Caddyfile only proxies. WhiteNoise inside the `web` container handles `/static/`. Don't add a `handle /static/*` block pointing at a host path — `web` is the only thing that has the collected files (they live inside the image), so a Caddy block would 404.

If the project also serves user-uploaded media via a shared volume (i.e. media on the VPS host, not S3 — see `references/storage-whitenoise.md`), serve it through Caddy:

```
example.com {     # replace with the real domain
    handle /media/* {
        uri strip_prefix /media   # without this, file_server resolves /srv/media/media/<file>
        root * /srv/media
        file_server
    }
    reverse_proxy web:8000
}
```

Mount the same `media` named volume into the `caddy` service in `docker-compose.prod.yml` (`media:/srv/media:ro`) — the same volume `web` mounts at `/app/media`, so both read the same files.

## Deploy

```sh
ssh user@vps
cd /srv/{project_slug}
git pull
# --env-file is required on every compose call — compose auto-loads only ./.env, not deploy/.env.prod
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml pull
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
```

Migrations run as a one-shot `docker compose run` *before* `up -d`. Compose's `depends_on: condition: service_healthy` (wired in `references/docker.md`) gates `web` on Postgres being ready — no `entrypoint.sh`, no `pg_isready` loop, no `migrate --noinput` baked into container start. The container's job is `gunicorn`, full stop. (Exception: the SQLite + Litestream pattern in `references/database.md` legitimately uses an entrypoint to restore the DB from S3 before launching gunicorn under `litestream replicate`.)
