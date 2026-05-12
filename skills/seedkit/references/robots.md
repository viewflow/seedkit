# robots.txt

Trivial endpoint — no package needed.

Put the view in `config/views.py`. If a suitable app already exists (a `core` app, a landing-page app), put it there instead — don't add a new app just for this view.

## `config/views.py`

```python
from django.conf import settings
from django.http import HttpResponse
from django.views.decorators.http import require_GET


@require_GET
def robots_txt(_request):
    if settings.DEBUG or getattr(settings, 'ROBOTS_DISALLOW_ALL', False):
        body = 'User-agent: *\nDisallow: /\n'
    else:
        body = (
            'User-agent: *\n'
            'Disallow: /admin/\n'
            'Disallow: /accounts/\n'
            'Allow: /\n'
        )
        sitemap = getattr(settings, 'SITEMAP_URL', None)
        if sitemap:
            body += f'\nSitemap: {sitemap}\n'
    return HttpResponse(body, content_type='text/plain')
```

## `config/urls.py`

```python
from django.urls import path
from config.views import robots_txt

urlpatterns = [
    # ...
    path('robots.txt', robots_txt, name='robots'),
]
```

## When to disallow everything

Staging deploys, preview environments, internal tools — set `ROBOTS_DISALLOW_ALL=True` in `.env` for those, leave it unset in production. Don't rely on `DEBUG` alone (a misconfigured prod with `DEBUG=True` would expose the site to crawlers anyway).

## What this is NOT

- Not a sitemap. If the project needs one, use `django.contrib.sitemaps` separately and point at it via `SITEMAP_URL`.
- Not a security control. Crawlers that ignore `robots.txt` won't be deterred — `/admin/` is gated by Django's auth, not by this file.
