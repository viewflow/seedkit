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

## Deploy

```sh
ssh user@vps
cd /srv/{project_slug}
git pull
docker compose -f deploy/docker-compose.prod.yml pull
docker compose -f deploy/docker-compose.prod.yml run --rm web uv run manage.py migrate
docker compose -f deploy/docker-compose.prod.yml up -d
```
