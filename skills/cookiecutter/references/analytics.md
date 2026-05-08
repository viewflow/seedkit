# Analytics

Privacy-respecting site analytics. Pick one backend at setup time — only that snippet ships in templates. Empty `ANALYTICS_ID` disables tracking (e.g. in dev).

| Backend | Reference | Hosting | Cookies | Consent banner |
|---|---|---|---|---|
| GoatCounter (recommended) | `analytics-goatcounter.md` | self-host or SaaS | no | no |
| Umami | `analytics-umami.md` | self-host or SaaS | no | no |
| Shynet | `analytics-shynet.md` | self-host | no | no |
| Google Analytics 4 | `analytics-ga4.md` | SaaS (US) | yes | **yes (EU)** |

GDPR / consent specifics — `references/gdpr.md`.

## Django wiring (shared)

Apply once for any chosen backend, then load the per-backend reference for its snippet.

### .env

```sh
ANALYTICS_ID=
ANALYTICS_HOST=     # only for self-hosted GoatCounter / Umami / Shynet
```

### Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
ANALYTICS_ID   = env("ANALYTICS_ID", default="")
ANALYTICS_HOST = env("ANALYTICS_HOST", default="")   # omit for GA4
```

### Context processor

`config/context_processors.py`:

```python
from django.conf import settings

def analytics(request):
    return {
        "ANALYTICS_ID":   settings.ANALYTICS_ID,
        "ANALYTICS_HOST": settings.ANALYTICS_HOST,
    }
```

Register in `TEMPLATES[0]["OPTIONS"]["context_processors"]`:

```python
"config.context_processors.analytics",
```

### Template

`templates/_analytics.html` wraps the chosen backend's snippet. The `not debug` gate keeps beacons out of dev:

```django
{% if ANALYTICS_ID and not debug %}
  {# backend snippet — see the per-backend reference #}
{% endif %}
```

In `templates/base.html`, before `</body>`:

```django
{% include "_analytics.html" %}
```

### SPA frontends (React / Vue / Next)

Analytics IDs aren't secrets. Two patterns:

**A. Django serves the SPA shell.** Use the context processor; inject IDs as a window global before the bundle loads:

```django
{% if ANALYTICS_ID and not debug %}
<script>
  window.__ANALYTICS__ = {
    id:   "{{ ANALYTICS_ID }}",
    host: "{{ ANALYTICS_HOST }}",
  };
</script>
{% endif %}
```

**B. Decoupled SPA** (Vite / Next, Django is API-only). Use build-time env vars (`VITE_ANALYTICS_ID`, `NEXT_PUBLIC_ANALYTICS_ID`), or a runtime config endpoint:

```python
def config(request):
    return JsonResponse({
        "analytics_id":   settings.ANALYTICS_ID,
        "analytics_host": settings.ANALYTICS_HOST,
    })
```

The SPA fetches `/api/config` once on boot, then injects the vendor `<script>` and calls the tracking API.

**Route-change pageviews.** SPAs don't trigger full page loads, so the vendor script's auto-pageview fires once. Re-fire on route change:

| Backend | Pageview call |
|---|---|
| GoatCounter | `window.goatcounter.count({ path: location.pathname })` |
| Umami | `window.umami.track()` |
| Shynet | (auto via heartbeat) |
| GA4 | `gtag('event', 'page_view', { page_path: location.pathname })` |

Wire it to the router — `useEffect(..., [location.pathname])` in React, router subscriber in Vue.
