# Email

Stock Django wires email backend / host / port / user / pass / tls one setting at a time. This reference uses `django-environ`'s `email_url` parser: a single `EMAIL_URL` env var (`consolemail://`, `smtp+tls://user:pass@host:port`, …) drives everything. Same shape as `DATABASE_URL`; swap providers without touching code.

## Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
# Gated default keeps dev zero-config but fails fast in prod (where DEBUG
# is unset). Without the gate, a missing EMAIL_URL silently routes prod
# mail to stdout via consolemail://.
globals().update(env.email_url("EMAIL_URL", default="consolemail://" if DEBUG else None))

DEFAULT_FROM_EMAIL = env(
    "DEFAULT_FROM_EMAIL",
    default="webmaster@localhost" if DEBUG else None,
)
SERVER_EMAIL = env("SERVER_EMAIL", default=DEFAULT_FROM_EMAIL)

ADMINS = [(email.split("@")[0], email) for email in env.list("DJANGO_ADMINS", default=[])]
MANAGERS = ADMINS
```

`ADMINS` receive 500-error emails (when `DEBUG=False`) and any `mail_admins()` call. Leave empty in dev — console backend prints to stdout anyway.

If allauth is configured with `ACCOUNT_EMAIL_VERIFICATION = "mandatory"` in production, the gated default is what saves you: console backend would block every signup because the verification link only goes to stdout. Production must set `EMAIL_URL` to a real SMTP URL.

`EMAIL_URL` schemes:

- `consolemail://` — print to stdout (dev default)
- `smtp://user:pass@host:port` — plain SMTP
- `smtp+tls://user:pass@host:port` — STARTTLS (port 587)
- `smtp+ssl://user:pass@host:port` — implicit TLS (port 465)
- `dummymail://` — drop silently (tests)

## .env (local)

```sh
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=webmaster@localhost
```

Also append to `.env.example` so the var is discoverable:

```sh
EMAIL_URL=consolemail://
# DEFAULT_FROM_EMAIL=webmaster@localhost
# SERVER_EMAIL=root@example.com
# DJANGO_ADMINS=admin@example.com,ops@example.com
```

## .env.prod (VPS)

Pick the URL matching your provider:

```sh
# Postmark SMTP
EMAIL_URL=smtp+tls://<server-token>:<server-token>@smtp.postmarkapp.com:587
# SendGrid SMTP
EMAIL_URL=smtp+tls://apikey:<api-key>@smtp.sendgrid.net:587
# Mailgun SMTP
EMAIL_URL=smtp+tls://<smtp-user>:<smtp-password>@smtp.mailgun.org:587
# AWS SES SMTP
EMAIL_URL=smtp+tls://<smtp-user>:<smtp-password>@email-smtp.<region>.amazonaws.com:587

DEFAULT_FROM_EMAIL=no-reply@example.com
SERVER_EMAIL=django@example.com
DJANGO_ADMINS=ops@example.com,alerts@example.com
```

URL-encode special characters in the password (`%40` for `@`, `%23` for `#`).

---

## Provider HTTP APIs (django-anymail)

SMTP works everywhere but is slower than provider HTTP APIs and exposes none of the provider's features (templated emails, click tracking, event webhooks). `django-anymail` ships per-provider `EmailBackend` classes that talk the provider's HTTP API instead.

Pick this over SMTP when:

- The provider charges per-message and you want delivery-event webhooks (delivered / bounced / complained / opened).
- You want to use server-stored templates with merge variables instead of rendering MIME locally.
- The platform blocks outbound port 587 (some serverless / managed runtimes do).

### Install

Pick the provider extra at install time:

```sh
uv add 'django-anymail[postmark]'      # or [amazon-ses], [sendgrid], [mailgun], [mandrill], [sparkpost], [brevo]
```

### Settings

Anymail's `EMAIL_BACKEND` overrides whatever `EMAIL_URL` parsed, so the `globals().update(env.email_url(...))` line above is fine to keep — it remains the dev fallback when `EMAIL_BACKEND` isn't set.

```python
INSTALLED_APPS += ["anymail"]

# Use provider API in prod; consolemail in dev. Same gating shape as
# the rest of the foundation.
if not DEBUG:
    EMAIL_BACKEND = "anymail.backends.postmark.EmailBackend"

ANYMAIL = {
    "POSTMARK_SERVER_TOKEN": env("POSTMARK_SERVER_TOKEN", default="" if DEBUG else None),
    # Provider-specific keys — see anymail.readthedocs.io for the full list.
    # SES: "AMAZON_SES_CLIENT_PARAMS", or use boto3's standard env vars.
    # SendGrid: "SENDGRID_API_KEY".
    # Mailgun: "MAILGUN_API_KEY", "MAILGUN_SENDER_DOMAIN".
}
```

### .env.prod

```sh
POSTMARK_SERVER_TOKEN=<token>
DEFAULT_FROM_EMAIL=no-reply@example.com
SERVER_EMAIL=django@example.com
```

`EMAIL_URL` is no longer needed in prod with this setup — `EMAIL_BACKEND` wins.

### Webhooks (optional)

Provider event webhooks (delivered / bounced / opened / clicked) need a Django URL exposed:

```python
# config/urls.py
urlpatterns = [
    ...
    path("anymail/", include("anymail.urls")),
]
```

```python
# settings — protect against forged webhook calls
ANYMAIL["WEBHOOK_SECRET"] = env("ANYMAIL_WEBHOOK_SECRET", default="" if DEBUG else None)
```

The provider needs configuring with `ANYMAIL_WEBHOOK_SECRET` as HTTP basic auth (`https://<secret>@example.com/anymail/<provider>/tracking/`). Connect signals to react to events:

```python
from anymail.signals import tracking

def handle_event(sender, event, esp_name, **kwargs):
    # event.event_type: "delivered", "bounced", "opened", ...
    ...

tracking.connect(handle_event)
```

---

## Managed platforms

Set `EMAIL_URL` and `DEFAULT_FROM_EMAIL` as platform env vars.

- **Fly.io**: `fly secrets set EMAIL_URL=... DEFAULT_FROM_EMAIL=...`
- **Railway / Render**: project-variables UI.

## Sending

```python
from django.core.mail import send_mail

send_mail(
    subject="Welcome",
    message="Thanks for signing up.",
    from_email=None,  # uses DEFAULT_FROM_EMAIL
    recipient_list=["user@example.com"],
)
```

Application mail uses `DEFAULT_FROM_EMAIL`; error reports to `ADMINS` use `SERVER_EMAIL`.

For multi-recipient broadcasts (newsletters, daily digests) **never** pass the full address list as `recipient_list=` — every recipient sees every other recipient's address in the `To:` header. Loop and send one message per user, or build an `EmailMessage` with `bcc=` set:

```python
for email in addresses:
    send_mail("Daily digest", body, None, [email])     # one per user

# or, single-shot via BCC:
EmailMessage(
    subject="Daily digest",
    body=body,
    to=["no-reply@example.com"],
    bcc=addresses,
).send()
```

---

## Optional — Mailpit for local HTML preview

Apply only if the user wants a web UI to inspect rendered emails locally.

### docker-compose.yml

```yaml
services:
  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "8025:8025"  # web UI
      - "1025:1025"  # SMTP
    environment:
      MP_MAX_MESSAGES: 5000
      MP_SMTP_AUTH_ACCEPT_ANY: 1
      MP_SMTP_AUTH_ALLOW_INSECURE: 1
```

### .env

```sh
EMAIL_URL=smtp://mailpit:1025
```

Open <http://localhost:8025> to view captured emails.
