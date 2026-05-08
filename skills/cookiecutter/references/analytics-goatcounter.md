# Analytics — GoatCounter

Tiny single Go binary, SQLite, cookieless. Lowest ops cost. Apply `analytics.md` (Django wiring) first.

**SaaS:** free at goatcounter.com — `ANALYTICS_HOST=https://<code>.goatcounter.com`, `ANALYTICS_ID=<code>`.

**Self-host (docker-compose.prod.yml):**

```yaml
services:
  goatcounter:
    image: arp242/goatcounter:latest
    restart: unless-stopped
    environment:
      GOATCOUNTER_LISTEN: ":8080"
    volumes:
      - goatcounter_data:/home/user/db

volumes:
  goatcounter_data:
```

Reverse-proxy `stats.example.com` → `goatcounter:8080`.

**Snippet** in `templates/_analytics.html`:

```html
<script data-goatcounter="{{ ANALYTICS_HOST }}/count"
        async src="//gc.zgo.at/count.js"></script>
```
