# Analytics — Shynet

Django + Postgres. Same stack as the project; cookieless via short-lived heartbeats. Apply `analytics.md` (Django wiring) first.

**Self-host (docker-compose.prod.yml):**

```yaml
services:
  shynet:
    image: milesmcc/shynet:latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://shynet:${SHYNET_DB_PASSWORD}@shynet-db:5432/shynet
      DJANGO_SECRET_KEY: ${SHYNET_SECRET_KEY}
      ALLOWED_HOSTS: stats.example.com
    depends_on: [shynet-db]

  shynet-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: shynet
      POSTGRES_USER: shynet
      POSTGRES_PASSWORD: ${SHYNET_DB_PASSWORD}
    volumes:
      - shynet_pgdata:/var/lib/postgresql/data

volumes:
  shynet_pgdata:
```

Reverse-proxy `stats.example.com` → `shynet:8080`. Create a Service in the Shynet admin; it generates the snippet — paste into `_analytics.html`. The service ID is `ANALYTICS_ID`.
