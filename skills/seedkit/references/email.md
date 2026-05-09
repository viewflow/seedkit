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
