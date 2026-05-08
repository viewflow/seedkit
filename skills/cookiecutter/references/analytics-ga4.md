# Analytics — Google Analytics 4

SaaS, US-hosted. Cookies required. **EU users need a consent banner before loading gtag** — see `references/gdpr.md`.

Apply `analytics.md` (Django wiring) first.

`ANALYTICS_ID=G-XXXXXXX` from analytics.google.com. `ANALYTICS_HOST` unused.

**Snippet** in `templates/_analytics.html`:

```html
<script async src="https://www.googletagmanager.com/gtag/js?id={{ ANALYTICS_ID }}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '{{ ANALYTICS_ID }}');
</script>
```
