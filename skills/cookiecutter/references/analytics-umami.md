# Analytics — Umami

Polished UI, cookieless. Node + Postgres. Apply `analytics.md` (Django wiring) first.

**SaaS:** umami.is.

**Self-host (docker-compose.prod.yml):**

```yaml
services:
  umami:
    image: ghcr.io/umami-software/umami:postgresql-latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://umami:${UMAMI_DB_PASSWORD}@umami-db:5432/umami
      DATABASE_TYPE: postgresql
      APP_SECRET: ${UMAMI_APP_SECRET}
    depends_on: [umami-db]

  umami-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: umami
      POSTGRES_USER: umami
      POSTGRES_PASSWORD: ${UMAMI_DB_PASSWORD}
    volumes:
      - umami_pgdata:/var/lib/postgresql/data

volumes:
  umami_pgdata:
```

Reverse-proxy `stats.example.com` → `umami:3000`. Create a website in the Umami UI to get the website ID.

**Snippet** in `templates/_analytics.html`:

```html
<script defer src="{{ ANALYTICS_HOST }}/script.js"
        data-website-id="{{ ANALYTICS_ID }}"></script>
```
