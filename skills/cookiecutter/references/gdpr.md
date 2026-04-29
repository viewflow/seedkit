# GDPR / privacy

Concrete settings for projects with EU users or regulated data.

## Sentry SDK — strip PII

```python
def _scrub(event, hint):
    request = event.get("request") or {}
    headers = request.get("headers") or {}
    for h in ("Authorization", "Cookie"):
        headers.pop(h, None)
    return event

sentry_sdk.init(
    dsn=SENTRY_DSN,
    integrations=[DjangoIntegration()],
    send_default_pii=False,
    before_send=_scrub,
)
```

## Data residency

| Backend | Where data lives |
|---------|------------------|
| Bugsink / GlitchTip (self-hosted) | Your VPS |
| Sentry SaaS — EU region | de.sentry.io (choose at signup) |
| Sentry SaaS — US region | sentry.io |

## Retention

- Bugsink: `RETENTION_*` env vars per project.
- GlitchTip: per-organization in admin UI.
- App data (user models, audit log): periodic task that deletes records past retention.

## Cookies / sessions

`SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` — `references/security.md`.

Add `SESSION_COOKIE_SAMESITE = "Lax"` if not using cross-site auth.

## Logging

Don't log request bodies or `Authorization` headers. With structured logging add a filter that drops these keys.

## User data export & deletion

Management commands:

```sh
manage.py export_user_data <user_id> > data.json
manage.py delete_user <user_id>
```

Implement deletion as a transaction that cascades to user-owned rows and writes an entry to an immutable audit log.
